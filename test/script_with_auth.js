// =============================================
// CONFIGURAÇÃO E VARIÁVEIS GLOBAIS
// =============================================
const API_BASE = `${window.ENV.SUPABASE_URL}/functions/v1`;

let currentUser = null;

// =============================================
// ELEMENTOS DO DOM
// =============================================
const loginScreen = document.getElementById('loginScreen');
const mainPanel = document.getElementById('mainPanel');
const loginForm = document.getElementById('loginForm');
const loginBtn = document.getElementById('loginBtn');
const loginMessage = document.getElementById('loginMessage');
const logoutBtn = document.getElementById('logoutBtn');
const userEmailSpan = document.getElementById('userEmail');
const message = document.getElementById('message');

// =============================================
// FUNÇÕES DE MENSAGEM
// =============================================
function showMessage(text, type = 'info') {
  message.textContent = text;
  message.className = type; // usa classes CSS como .success / .error / .info
}

function showLoginMessage(text, type = 'info') {
  loginMessage.textContent = text;
  loginMessage.className = `login-message ${type}`;
}

// =============================================
// AUTENTICAÇÃO
// =============================================
async function login(email, password) {
  try {
    const res = await fetch(`${window.ENV.SUPABASE_URL}/functions/v1/auth-login`, {
      method: 'POST',
      headers: { 
        'Content-Type': 'application/json',
        'apikey': window.ENV.SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${window.ENV.SUPABASE_ANON_KEY}`
      },
      body: JSON.stringify({ email, password }),
    });

    const data = await res.json();

    if (!res.ok) {
      throw new Error(data.message || 'Erro ao fazer login');
    }

    return data;
  } catch (err) {
    throw err;
  }
}

function saveSession(user) {
  localStorage.setItem('currentUser', JSON.stringify(user));
  currentUser = user;
}

function loadSession() {
  const saved = localStorage.getItem('currentUser');
  if (saved) {
    currentUser = JSON.parse(saved);
    return true;
  }
  return false;
}

function clearSession() {
  localStorage.removeItem('currentUser');
  currentUser = null;
}

function showMainPanel() {
  loginScreen.style.display = 'none';
  mainPanel.style.display = 'block';
  userEmailSpan.textContent = currentUser.email;
}

function showLoginScreen() {
  loginScreen.style.display = 'flex';
  mainPanel.style.display = 'none';
  loginMessage.textContent = '';
}

// =============================================
// EVENT LISTENERS - AUTENTICAÇÃO
// =============================================
loginForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  
  const email = document.getElementById('loginEmail').value.trim();
  const password = document.getElementById('loginPassword').value;

  if (!email || !password) {
    showLoginMessage('Por favor, preencha todos os campos.', 'error');
    return;
  }

  showLoginMessage('Autenticando...', 'info');
  loginBtn.disabled = true;
  loginBtn.textContent = 'Entrando...';

  try {
    const userData = await login(email, password);
    saveSession(userData.user);
    showMainPanel();
    showMessage('Login realizado com sucesso!', 'success');
  } catch (err) {
    showLoginMessage(`❌ ${err.message}`, 'error');
  } finally {
    loginBtn.disabled = false;
    loginBtn.textContent = 'Entrar';
  }
});

logoutBtn.addEventListener('click', () => {
  clearSession();
  showLoginScreen();
  showLoginMessage('Você saiu com sucesso.', 'success');
});

// =============================================
// VERIFICAÇÃO DE SESSÃO AO CARREGAR
// =============================================
window.addEventListener('DOMContentLoaded', () => {
  if (loadSession()) {
    showMainPanel();
  } else {
    showLoginScreen();
  }
});

// =============================================
// FUNCIONALIDADES EXISTENTES (EXPORTAR CSV, EMAIL, CONSULTAR)
// =============================================
const exportBtn = document.getElementById('exportCsvBtn');
const emailBtn = document.getElementById('sendEmailBtn');

exportBtn.addEventListener('click', async () => {
  const customerId = document.getElementById('customerId').value.trim();
  if (!customerId) return showMessage('Por favor, forneça o ID do cliente.', 'error');

  showMessage('Gerando CSV...', 'info');
  exportBtn.disabled = true;
  exportBtn.textContent = 'Processando...';

  try {
    const res = await fetch(`${API_BASE}/export-csv`, {
      method: 'POST',
      headers: { 
        'Content-Type': 'application/json',
        'apikey': window.ENV.SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${window.ENV.SUPABASE_ANON_KEY}`
      },
      body: JSON.stringify({ customerId }),
    });

    if (!res.ok) {
      const errorData = await res.json().catch(() => ({}));
      throw new Error(errorData.message || 'Erro ao exportar CSV');
    }

    const blob = await res.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `orders_${customerId}.csv`;
    a.click();
    window.URL.revokeObjectURL(url);

    showMessage('CSV exportado com sucesso!', 'success');
  } catch (err) {
    showMessage(`❌ ${err.message}`, 'error');
  } finally {
    exportBtn.disabled = false;
    exportBtn.textContent = 'Exportar CSV';
  }
});

emailBtn.addEventListener('click', async () => {
  const email = document.getElementById('email').value.trim();
  const orderId = document.getElementById('orderId').value.trim();
  if (!email || !orderId)
    return showMessage('Por favor, forneça o e-mail e o ID do pedido.', 'error');

  showMessage('Enviando e-mail...', 'info');
  emailBtn.disabled = true;
  emailBtn.textContent = 'Enviando...';

  try {
    const res = await fetch(`${API_BASE}/send-confirmation-email`, {
      method: 'POST',
      headers: { 
        'Content-Type': 'application/json',
        'apikey': window.ENV.SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${window.ENV.SUPABASE_ANON_KEY}`
      },
      body: JSON.stringify({ email, orderId }),
    });

    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.message || 'Erro ao enviar e-mail');

    showMessage('E-mail enviado com sucesso!', 'success');
  } catch (err) {
    showMessage(`❌ ${err.message}`, 'error');
  } finally {
    emailBtn.disabled = false;
    emailBtn.textContent = 'Enviar E-mail';
  }
});

const queryBtn = document.getElementById('queryOrdersBtn');
const ordersTable = document.getElementById('ordersTable').querySelector('tbody');

queryBtn.addEventListener('click', async () => {
  const customerId = document.getElementById('customerIdQuery').value.trim();
  if (!customerId) return showMessage('Por favor, forneça o ID do cliente.', 'error');

  showMessage('Buscando pedidos...', 'info');
  queryBtn.disabled = true;
  queryBtn.textContent = 'Carregando...';
  ordersTable.innerHTML = '';

  try {
    const res = await fetch(
      `${window.ENV.SUPABASE_URL}/rest/v1/view_orders_with_customers?customer_id=eq.${customerId}`,
      {
        headers: {
          apikey: window.ENV.SUPABASE_ANON_KEY,
          Authorization: `Bearer ${window.ENV.SUPABASE_ANON_KEY}`,
        },
      }
    );

    if (!res.ok) throw new Error('Erro ao buscar pedidos');
    const data = await res.json();

    if (!data || data.length === 0) {
      showMessage('Nenhum pedido encontrado.', 'info');
      queryBtn.textContent = 'Consultar Pedidos';
      queryBtn.disabled = false;
      return;
    }

    data.forEach((order) => {
      const row = document.createElement('tr');
      row.innerHTML = `
        <td>${order.order_id}</td>
        <td>${order.status}</td>
        <td>R$ ${order.total_amount.toFixed(2)}</td>
        <td>${new Date(order.order_date).toLocaleDateString('pt-BR')}</td>
      `;
      ordersTable.appendChild(row);
    });

    showMessage('Pedidos carregados com sucesso!', 'success');
  } catch (err) {
    showMessage(`❌ ${err.message}`, 'error');
  } finally {
    queryBtn.disabled = false;
    queryBtn.textContent = 'Consultar Pedidos';
  }
});
