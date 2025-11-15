// ------------ Guard-rails de ENV ------------
if (!window.ENV?.SUPABASE_URL || !window.ENV?.SUPABASE_ANON_KEY) {
  throw new Error('Configuração ausente: defina SUPABASE_URL e SUPABASE_ANON_KEY em env.js');
}

// ------------ Config / Estado ------------
const API_BASE = `${window.ENV.SUPABASE_URL}/functions/v1`;
let currentSession = null;

// ------------ DOM ------------
const qs = (sel) => document.querySelector(sel);
const loginScreen = qs('#loginScreen');
const mainPanel   = qs('#mainPanel');
const loginForm   = qs('#loginForm');
const loginBtn    = qs('#loginBtn');
const loginMessage= qs('#loginMessage');
const logoutBtn   = qs('#logoutBtn');
const userEmail   = qs('#userEmail');
const exportForm  = qs('#exportForm');
const emailForm   = qs('#emailForm');
const queryForm   = qs('#queryForm');
const exportBtn   = qs('#exportCsvBtn');
const emailBtn    = qs('#sendEmailBtn');
const queryBtn    = qs('#queryOrdersBtn');
const tableWrap   = qs('.table-wrapper');
const ordersTBody = qs('#ordersTable tbody');
const messageEl   = qs('#message');

// ------------ Utils ------------
const emailRe = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const uuidV4  = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const withButtonLoading = async (btn, labelLoading, fn) => {
  const prev = btn.textContent;
  btn.disabled = true;
  btn.textContent = labelLoading;
  try { return await fn(); }
  finally { btn.disabled = false; btn.textContent = prev; }
};

const showMessage = (text, type = 'info') => {
  messageEl.textContent = text;
  messageEl.className = `message ${type}`; // use .message + modifiers
};

const setBusy = (busy) => {
  tableWrap.setAttribute('aria-busy', busy ? 'true' : 'false');
};

// Wrapper genérico de fetch com tratamento consistente
async function apiFetch(url, options = {}) {
  const headers = new Headers(options.headers || {});
  headers.set('Content-Type', 'application/json');
  headers.set('apikey', window.ENV.SUPABASE_ANON_KEY);

  const bearer = currentSession?.access_token;
  if (bearer) headers.set('Authorization', `Bearer ${bearer}`);

  const res = await fetch(url, { ...options, headers });
  const contentType = res.headers.get('Content-Type') || '';

  // Tenta parsear JSON se fizer sentido
  const tryParseJSON = async () => {
    if (contentType.includes('application/json')) {
      try { return await res.json(); } catch { return null; }
    }
    return null;
  };

  if (!res.ok) {
    const data = await tryParseJSON();
    const msg = data?.message || data?.error || `Erro HTTP ${res.status}`;
    throw new Error(msg);
  }

  return { res, json: await tryParseJSON(), contentType };
}

// ------------ Sessão ------------
function saveSession({ user, session }) {
  const payload = {
    user,
    access_token: session?.access_token ?? null,
    refresh_token: session?.refresh_token ?? null,
    expires_at: session?.expires_at ?? null,
  };
  localStorage.setItem('sb_session', JSON.stringify(payload));
  currentSession = payload;
}
function loadSession() {
  try {
    const raw = localStorage.getItem('sb_session');
    if (!raw) return false;
    currentSession = JSON.parse(raw);
    return !!currentSession?.access_token;
  } catch { return false; }
}
function clearSession() {
  localStorage.removeItem('sb_session');
  currentSession = null;
}

// ------------ UI ------------
function showMain() {
  loginScreen.classList.add('hidden');
  mainPanel.classList.remove('hidden');
  userEmail.textContent = currentSession?.user?.email ?? '';
}
function showLogin() {
  mainPanel.classList.add('hidden');
  loginScreen.classList.remove('hidden');
  loginMessage.textContent = '';
}
const showLoginMessage = (text, type='info') => {
  loginMessage.textContent = text;
  loginMessage.className = `login-message ${type}`;
};

// ------------ Auth ------------
async function login(email, password) {
  const { json } = await apiFetch(`${API_BASE}/auth-login`, {
    method: 'POST',
    body: JSON.stringify({ email, password }),
  });
  return json; // { user, session }
}

// ------------ Eventos ------------
loginForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  const email = qs('#loginEmail').value.trim();
  const password = qs('#loginPassword').value;

  if (!email || !password) return showLoginMessage('Preencha e-mail e senha.', 'error');
  if (!emailRe.test(email)) return showLoginMessage('E-mail inválido.', 'error');

  await withButtonLoading(loginBtn, 'Entrando…', async () => {
    showLoginMessage('Autenticando…', 'info');
    const payload = await login(email, password);
    saveSession(payload);
    showMain();
    showMessage('Login realizado com sucesso!', 'success');
  }).catch(err => showLoginMessage(`❌ ${err.message}`, 'error'));
});

logoutBtn.addEventListener('click', () => {
  clearSession();
  showLogin();
  showLoginMessage('Você saiu com sucesso.', 'success');
});

// Boot
window.addEventListener('DOMContentLoaded', () => {
  loadSession() ? showMain() : showLogin();
});

// ------------ Ações ------------
exportForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  const customerId = qs('#customerId').value.trim();
  if (!uuidV4.test(customerId)) return showMessage('customerId inválido (UUID v4).', 'error');
  if (!currentSession?.access_token) return showMessage('Sessão expirada. Faça login.', 'error');

  await withButtonLoading(exportBtn, 'Processando…', async () => {
    showMessage('Gerando CSV…', 'info');
    const { res, contentType } = await apiFetch(`${API_BASE}/export-csv`, {
      method: 'POST',
      body: JSON.stringify({ customerId }),
    });

    if (!contentType.includes('text/csv')) throw new Error('Resposta não é CSV.');
    const blob = await res.blob();
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `orders_${customerId}.csv`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
    showMessage('CSV exportado com sucesso!', 'success');
  }).catch(err => showMessage(`❌ ${err.message}`, 'error'));
});

emailForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  const email = qs('#email').value.trim();
  const orderId = qs('#orderId').value.trim();

  if (!emailRe.test(email)) return showMessage('E-mail inválido.', 'error');
  if (!uuidV4.test(orderId)) return showMessage('orderId inválido (UUID v4).', 'error');
  if (!currentSession?.access_token) return showMessage('Sessão expirada. Faça login.', 'error');

  await withButtonLoading(emailBtn, 'Enviando…', async () => {
    showMessage('Enviando e-mail…', 'info');
    await apiFetch(`${API_BASE}/send-confirmation-email`, {
      method: 'POST',
      body: JSON.stringify({ email, orderId }),
    });
    showMessage('E-mail enviado com sucesso!', 'success');
  }).catch(err => showMessage(`❌ ${err.message}`, 'error'));
});

queryForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  const customerId = qs('#customerIdQuery').value.trim();

  if (!uuidV4.test(customerId)) return showMessage('customerId inválido (UUID v4).', 'error');
  if (!currentSession?.access_token) return showMessage('Sessão expirada. Faça login.', 'error');

  await withButtonLoading(queryBtn, 'Carregando…', async () => {
    setBusy(true);
    showMessage('Buscando pedidos…', 'info');

    const { json: data } = await apiFetch(
      `${window.ENV.SUPABASE_URL}/rest/v1/view_orders_with_customers?customer_id=eq.${customerId}`,
      { method: 'GET' }
    );

    ordersTBody.textContent = ''; // limpa seguro

    if (!Array.isArray(data) || data.length === 0) {
      showMessage('Nenhum pedido encontrado.', 'info');
      return;
    }

    for (const order of data) {
      const tr = document.createElement('tr');

      const tdId = document.createElement('td');
      tdId.textContent = String(order.order_id ?? '');
      const tdSt = document.createElement('td');
      tdSt.textContent = String(order.status ?? '');
      const tdTot = document.createElement('td');
      tdTot.textContent = `R$ ${Number(order.total_amount ?? 0).toFixed(2)}`;
      const tdDt = document.createElement('td');
      const when = order.order_date_formatted ||
                   new Date(order.order_created_at).toLocaleString('pt-BR');
      tdDt.textContent = when;

      tr.append(tdId, tdSt, tdTot, tdDt);
      ordersTBody.appendChild(tr);
    }

    showMessage('Pedidos carregados com sucesso!', 'success');
  }).catch(err => showMessage(`❌ ${err.message}`, 'error'))
    .finally(() => setBusy(false));
});
