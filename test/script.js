const exportBtn = document.getElementById('exportCsvBtn')
const emailBtn = document.getElementById('sendEmailBtn')
const message = document.getElementById('message')

const API_BASE =
  window.location.hostname === 'localhost'
    ? `${window.ENV.SUPABASE_URL}/functions/v1`
    : '/functions/v1';

function showMessage(text, type = 'info') {
  message.textContent = text
  message.className = type // usa classes CSS como .success / .error / .info
}

exportBtn.addEventListener('click', async () => {
  const customerId = document.getElementById('customerId').value.trim()
  if (!customerId) return showMessage('Please provide the customer ID.', 'error')

  showMessage('Generating CSV...', 'info')
  exportBtn.disabled = true
  exportBtn.textContent = 'Processing...'

  try {
    const res = await fetch(`${API_BASE}/export-csv`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ customerId }),
    })

    if (!res.ok) {
      const errorData = await res.json().catch(() => ({}))
      throw new Error(errorData.message || 'Error exporting CSV')
    }

    const blob = await res.blob()
    const url = window.URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `orders_${customerId}.csv`
    a.click()
    window.URL.revokeObjectURL(url)

    showMessage('CSV successfully exported!', 'success')
  } catch (err) {
    showMessage(`❌ ${err.message}`, 'error')
  } finally {
    exportBtn.disabled = false
    exportBtn.textContent = 'Export CSV'
  }
})

emailBtn.addEventListener('click', async () => {
  const email = document.getElementById('email').value.trim()
  const orderId = document.getElementById('orderId').value.trim()
  if (!email || !orderId)
    return showMessage('Please provide your email address and order ID.', 'error')

  showMessage('Sending email...', 'info')
  emailBtn.disabled = true
  emailBtn.textContent = 'Sending...'

  try {
    const res = await fetch(`${API_BASE}/send-confirmation-email`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, orderId }),
    })

    const data = await res.json().catch(() => ({}))
    if (!res.ok) throw new Error(data.message || 'Error sending email')

    showMessage('Email sent successfully!', 'success')
  } catch (err) {
    showMessage(`${err.message}`, 'error')
  } finally {
    emailBtn.disabled = false
    emailBtn.textContent = 'Send Email'
  }
})

const queryBtn = document.getElementById('queryOrdersBtn')
const ordersTable = document.getElementById('ordersTable').querySelector('tbody')

queryBtn.addEventListener('click', async () => {
  const customerId = document.getElementById('customerIdQuery').value.trim()
  if (!customerId) return showMessage('Please provide the customer ID.', 'error')

  showMessage('Searching for orders...', 'info')
  queryBtn.disabled = true
  queryBtn.textContent = 'Loading...'
  ordersTable.innerHTML = ''

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

    if (!res.ok) throw new Error('Error retrieving orders')
    const data = await res.json()

    if (!data || data.length === 0) {
      showMessage('No requests found.', 'info')
      queryBtn.textContent = 'View Orders'
      queryBtn.disabled = false
      return
    }

    data.forEach((order) => {
      const row = document.createElement('tr')
      row.innerHTML = `
        <td>${order.order_id}</td>
        <td>${order.status}</td>
        <td>R$ ${order.total_amount.toFixed(2)}</td>
        <td>${new Date(order.order_date).toLocaleDateString('pt-BR')}</td>
      `
      ordersTable.appendChild(row)
    })

    showMessage('Orders successfully uploaded!', 'success')
  } catch (err) {
    showMessage(`${err.message}`, 'error')
  } finally {
    queryBtn.disabled = false
    queryBtn.textContent = 'View Orders'
  }
})
