/**
 * APEXBANK PL/SQL - CLIENT APP LOGIC
 * Manages frontend state, REST API calls, DOM rendering, and terminal logging.
 */

let state = {
    accounts: [],
    transactions: [],
    audits: [],
    stats: {}
};

// ----------------------------------------------------------------------------
// INITIALIZATION
// ----------------------------------------------------------------------------
document.addEventListener('DOMContentLoaded', () => {
    loadAllData();
    // Auto-refresh stats and records every 10 seconds
    setInterval(loadAllData, 10000);
});

async function loadAllData() {
    await Promise.all([
        fetchStats(),
        fetchAccounts(),
        fetchTransactions(),
        fetchAudits()
    ]);
}

// ----------------------------------------------------------------------------
// NAVIGATION & TABS
// ----------------------------------------------------------------------------
function switchNav(tabId, el) {
    document.querySelectorAll('.nav-item').forEach(item => item.classList.remove('active'));
    document.querySelectorAll('.tab-section').forEach(sec => sec.classList.remove('active'));

    if (el) el.classList.add('active');
    const targetSection = document.getElementById(`section-${tabId}`);
    if (targetSection) targetSection.classList.add('active');

    // Title updates
    const titleMap = {
        'dashboard': { title: 'Banking Overview', sub: 'Real-time PL/SQL Transaction Management System' },
        'transfer': { title: 'Atomic Fund Transfer', sub: 'Pessimistic Row Locks & ACID Compliant Transfers' },
        'transactions': { title: 'Transaction Ledger', sub: 'Audit-ready financial movement ledger' },
        'audit': { title: 'Automated Audit Trail', sub: 'Real-time database trigger tracking via TRG_ACCOUNT_AUDIT' },
        'sql': { title: 'Live SQL Query Console', sub: 'Execute live queries against SQLite PL/SQL database' },
        'interest': { title: 'Batch Interest Cursor', sub: 'Simulate explicit cursor loops with FOR UPDATE & CURRENT OF' }
    };

    if (titleMap[tabId]) {
        document.getElementById('pageTitle').innerText = titleMap[tabId].title;
        document.getElementById('pageSubtitle').innerText = titleMap[tabId].sub;
    }
}

// ----------------------------------------------------------------------------
// API FETCHERS
// ----------------------------------------------------------------------------
async function fetchStats() {
    try {
        const res = await fetch('/api/stats');
        const json = await res.json();
        if (json.success) {
            state.stats = json.data;
            document.getElementById('statLiquidity').innerText = '₹' + state.stats.total_balance.toLocaleString('en-IN', {minimumFractionDigits: 2});
            document.getElementById('statAccounts').innerText = state.stats.total_accounts;
            document.getElementById('statTxns').innerText = state.stats.total_transactions;
            document.getElementById('statAudits').innerText = state.stats.total_audit_events;
        }
    } catch (e) {
        console.error('Error fetching stats:', e);
    }
}

async function fetchAccounts() {
    try {
        const res = await fetch('/api/accounts');
        const json = await res.json();
        if (json.success) {
            state.accounts = json.data;
            renderAccountCards();
            populateAccountDropdowns();
        }
    } catch (e) {
        console.error('Error fetching accounts:', e);
    }
}

async function fetchTransactions() {
    try {
        const res = await fetch('/api/transactions?limit=50');
        const json = await res.json();
        if (json.success) {
            state.transactions = json.data;
            renderTransactionsTable(state.transactions);
        }
    } catch (e) {
        console.error('Error fetching transactions:', e);
    }
}

async function fetchAudits() {
    try {
        const res = await fetch('/api/audit-logs?limit=50');
        const json = await res.json();
        if (json.success) {
            state.audits = json.data;
            renderAuditTable(state.audits);
        }
    } catch (e) {
        console.error('Error fetching audit logs:', e);
    }
}

// ----------------------------------------------------------------------------
// DOM RENDERERS
// ----------------------------------------------------------------------------
function renderAccountCards() {
    const container = document.getElementById('accountsCardsContainer');
    if (!container) return;

    container.innerHTML = state.accounts.map(acc => {
        const themeClass = acc.account_type === 'SAVINGS' ? 'card-theme-savings' :
                           acc.account_type === 'SALARY' ? 'card-theme-salary' : 'card-theme-current';
        
        return `
            <div class="bank-card ${themeClass}" onclick="openAccountDetails(${acc.account_no})">
                <div class="card-hologram"></div>
                <div class="card-top">
                    <div class="chip-wrap">
                        <div class="chip"></div>
                        <svg class="contactless-wave" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <path d="M8.5 16.5a5 5 0 0 1 0-9M12 19a8.5 8.5 0 0 0 0-14M15.5 21.5a12 12 0 0 0 0-19"/>
                        </svg>
                    </div>
                    <span class="card-tag">${acc.account_type}</span>
                </div>
                <div class="card-middle">
                    <div class="card-balance-label">Available Balance</div>
                    <div class="card-balance">₹${acc.balance.toLocaleString('en-IN', {minimumFractionDigits: 2})}</div>
                </div>
                <div class="card-bottom">
                    <div>
                        <div class="card-holder">${acc.holder_name}</div>
                        <div style="font-size: 11px; opacity: 0.7;">${acc.phone}</div>
                    </div>
                    <div class="card-number">•••• ${acc.account_no}</div>
                </div>
            </div>
        `;
    }).join('');
}

function populateAccountDropdowns() {
    const dropdownIds = ['dashFromAcc', 'dashToAcc', 'mainTransferFrom', 'mainTransferTo', 'depositAccSelect', 'withdrawAccSelect'];
    
    dropdownIds.forEach(id => {
        const el = document.getElementById(id);
        if (!el) return;
        const currentVal = el.value;
        el.innerHTML = '';

        state.accounts.forEach((acc, idx) => {
            const opt = document.createElement('option');
            opt.value = acc.account_no;
            opt.innerText = `#${acc.account_no} - ${acc.holder_name} (₹${acc.balance.toLocaleString('en-IN')})`;
            el.appendChild(opt);
        });

        if (currentVal && Array.from(el.options).some(o => o.value == currentVal)) {
            el.value = currentVal;
        } else if (id.includes('To') && state.accounts.length > 1) {
            el.selectedIndex = 1;
        }
    });

    updateTransferPreview();
}

function updateTransferPreview() {
    const fromEl = document.getElementById('mainTransferFrom');
    const toEl = document.getElementById('mainTransferTo');
    if (!fromEl || !toEl) return;

    const sAcc = state.accounts.find(a => a.account_no == fromEl.value);
    const rAcc = state.accounts.find(a => a.account_no == toEl.value);

    const sPrev = document.getElementById('senderBalancePreview');
    const rPrev = document.getElementById('receiverBalancePreview');

    if (sAcc && sPrev) sPrev.innerText = `Current Available: ₹${sAcc.balance.toLocaleString('en-IN', {minimumFractionDigits: 2})}`;
    if (rAcc && rPrev) rPrev.innerText = `Current Available: ₹${rAcc.balance.toLocaleString('en-IN', {minimumFractionDigits: 2})}`;
}

function renderTransactionsTable(txns) {
    const tbody = document.getElementById('transactionsTableBody');
    if (!tbody) return;

    tbody.innerHTML = txns.map(t => {
        const typeBadge = t.txn_type === 'TRANSFER' ? 'badge-transfer' :
                          t.txn_type === 'INTEREST' ? 'badge-interest' : 'badge-success';
        const statusBadge = t.status === 'SUCCESS' ? 'badge-success' : 'badge-failed';
        const color = t.txn_type === 'WITHDRAWAL' ? 'var(--rose)' : 'var(--emerald)';

        return `
            <tr>
                <td class="mono-cell">#${t.txn_id}</td>
                <td><span class="status-badge ${typeBadge}">${t.txn_type}</span></td>
                <td class="mono-cell">${t.from_account ? '#' + t.from_account : '-'}</td>
                <td class="mono-cell">${t.to_account ? '#' + t.to_account : '-'}</td>
                <td class="mono-cell" style="font-weight: 700; color: ${color};">
                    ₹${t.amount.toLocaleString('en-IN', {minimumFractionDigits: 2})}
                </td>
                <td><span class="status-badge ${statusBadge}">${t.status}</span></td>
                <td style="color: var(--text-muted); font-size: 11.5px;">${t.txn_date}</td>
                <td>${t.remarks || '-'}</td>
            </tr>
        `;
    }).join('');
}

function renderAuditTable(audits) {
    const tbody = document.getElementById('auditTableBody');
    if (!tbody) return;

    tbody.innerHTML = audits.map(a => `
        <tr>
            <td class="mono-cell">#${a.log_id}</td>
            <td class="mono-cell">#${a.account_no}</td>
            <td><span class="status-badge badge-transfer">${a.action_type}</span></td>
            <td class="mono-cell">₹${a.old_balance.toLocaleString('en-IN', {minimumFractionDigits: 2})}</td>
            <td class="mono-cell" style="font-weight: 700; color: var(--emerald);">
                ₹${a.new_balance.toLocaleString('en-IN', {minimumFractionDigits: 2})}
            </td>
            <td><code style="font-size: 11px; color: var(--text-muted);">${a.changed_by}</code></td>
            <td style="color: var(--text-muted); font-size: 11.5px;">${a.changed_at}</td>
        </tr>
    `).join('');
}

// ----------------------------------------------------------------------------
// TRANSACTION OPERATIONS (PROCEDURES)
// ----------------------------------------------------------------------------
async function handleDashTransfer() {
    const from = document.getElementById('dashFromAcc').value;
    const to = document.getElementById('dashToAcc').value;
    const amount = parseFloat(document.getElementById('dashAmount').value);
    const remarks = document.getElementById('dashRemarks').value || 'Fund Transfer';

    if (!amount || amount <= 0) {
        showToast('Please enter a valid transfer amount.', 'error');
        return;
    }

    logTerminal(`CALL BANKING_PKG.transfer_funds(${from}, ${to}, ${amount}, '${remarks}')`, 'plsql');

    try {
        const res = await fetch('/api/transfer', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ from_account: from, to_account: to, amount: amount, remarks: remarks })
        });
        const data = await res.json();
        if (data.success) {
            logTerminal(data.message, 'success');
            showToast(data.message, 'success');
            document.getElementById('dashAmount').value = '';
            await loadAllData();
        } else {
            logTerminal(`[EXCEPTION] ${data.error}`, 'error');
            showToast(data.error, 'error');
        }
    } catch (e) {
        logTerminal(`[NETWORK ERROR] ${e.message}`, 'error');
    }
}

async function handleMainTransfer() {
    const from = document.getElementById('mainTransferFrom').value;
    const to = document.getElementById('mainTransferTo').value;
    const amount = parseFloat(document.getElementById('mainTransferAmount').value);
    const remarks = document.getElementById('mainTransferRemarks').value || 'Fund Transfer';

    if (!amount || amount <= 0) {
        showToast('Please enter a valid transfer amount.', 'error');
        return;
    }

    logTerminal(`CALL BANKING_PKG.transfer_funds(${from}, ${to}, ${amount}, '${remarks}')`, 'plsql');

    try {
        const res = await fetch('/api/transfer', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ from_account: from, to_account: to, amount: amount, remarks: remarks })
        });
        const data = await res.json();
        if (data.success) {
            logTerminal(data.message, 'success');
            showToast(data.message, 'success');
            document.getElementById('mainTransferAmount').value = '';
            await loadAllData();
        } else {
            logTerminal(`[EXCEPTION] ${data.error}`, 'error');
            showToast(data.error, 'error');
        }
    } catch (e) {
        logTerminal(`[NETWORK ERROR] ${e.message}`, 'error');
    }
}

async function submitDeposit() {
    const acc = document.getElementById('depositAccSelect').value;
    const amount = parseFloat(document.getElementById('depositAmount').value);
    const remarks = document.getElementById('depositRemarks').value || 'Cash Deposit';

    if (!amount || amount <= 0) {
        showToast('Please enter a valid deposit amount.', 'error');
        return;
    }

    logTerminal(`CALL BANKING_PKG.deposit(${acc}, ${amount}, '${remarks}')`, 'plsql');
    try {
        const res = await fetch('/api/deposit', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ account_no: acc, amount: amount, remarks: remarks })
        });
        const data = await res.json();
        if (data.success) {
            logTerminal(data.message, 'success');
            showToast(data.message, 'success');
            closeModal('modalDeposit');
            document.getElementById('depositAmount').value = '';
            await loadAllData();
        } else {
            showToast(data.error, 'error');
        }
    } catch (e) {
        showToast(e.message, 'error');
    }
}

async function submitWithdraw() {
    const acc = document.getElementById('withdrawAccSelect').value;
    const amount = parseFloat(document.getElementById('withdrawAmount').value);
    const remarks = document.getElementById('withdrawRemarks').value || 'Cash Withdrawal';

    if (!amount || amount <= 0) {
        showToast('Please enter a valid withdrawal amount.', 'error');
        return;
    }

    logTerminal(`CALL BANKING_PKG.withdraw(${acc}, ${amount}, '${remarks}')`, 'plsql');
    try {
        const res = await fetch('/api/withdraw', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ account_no: acc, amount: amount, remarks: remarks })
        });
        const data = await res.json();
        if (data.success) {
            logTerminal(data.message, 'success');
            showToast(data.message, 'success');
            closeModal('modalWithdraw');
            document.getElementById('withdrawAmount').value = '';
            await loadAllData();
        } else {
            logTerminal(`[EXCEPTION] ${data.error}`, 'error');
            showToast(data.error, 'error');
        }
    } catch (e) {
        showToast(e.message, 'error');
    }
}

async function submitCreateAccount() {
    const name = document.getElementById('newAccName').value;
    const email = document.getElementById('newAccEmail').value;
    const phone = document.getElementById('newAccPhone').value;
    const type = document.getElementById('newAccType').value;
    const deposit = parseFloat(document.getElementById('newAccDeposit').value) || 0;

    if (!name || !email || !phone) {
        showToast('Please fill all required account fields.', 'error');
        return;
    }

    logTerminal(`CALL BANKING_PKG.open_account('${name}', '${email}', '${phone}', '${type}', ${deposit})`, 'plsql');
    try {
        const res = await fetch('/api/accounts', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ holder_name: name, email: email, phone: phone, account_type: type, initial_deposit: deposit })
        });
        const data = await res.json();
        if (data.success) {
            logTerminal(data.message, 'success');
            showToast(data.message, 'success');
            closeModal('modalCreateAccount');
            document.getElementById('newAccName').value = '';
            document.getElementById('newAccEmail').value = '';
            document.getElementById('newAccPhone').value = '';
            await loadAllData();
        } else {
            showToast(data.error, 'error');
        }
    } catch (e) {
        showToast(e.message, 'error');
    }
}

async function runInterestBatch() {
    const rate = parseFloat(document.getElementById('interestSlider').value) || 4.5;
    logTerminal(`CALL BANKING_PKG.apply_monthly_interest(${rate})... (Starting Cursor Loop)`, 'plsql');

    try {
        const res = await fetch('/api/interest', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ rate: rate })
        });
        const data = await res.json();
        if (data.success) {
            logTerminal(data.message, 'success');
            showToast(data.message, 'success');

            const detailsBox = document.getElementById('interestResultDetails');
            detailsBox.innerHTML = `
                <div style="background: rgba(16,185,129,0.1); border: 1px solid var(--emerald-border); padding: 14px; border-radius: 10px;">
                    <strong style="color: var(--emerald);">✔ Batch Execution Summary:</strong>
                    <div style="font-size: 13px; margin-top: 6px;">Accounts Credited: <strong>${data.data.accounts_credited}</strong></div>
                    <div style="font-size: 13px;">Total Interest Paid: <strong>₹${data.data.total_interest_paid.toLocaleString('en-IN', {minimumFractionDigits: 2})}</strong></div>
                </div>
            `;
            await loadAllData();
        } else {
            showToast(data.error, 'error');
        }
    } catch (e) {
        showToast(e.message, 'error');
    }
}

// ----------------------------------------------------------------------------
// SQL PLAYGROUND
// ----------------------------------------------------------------------------
function setQuery(q) {
    document.getElementById('sqlInput').value = q;
}

async function runCustomSQL() {
    const query = document.getElementById('sqlInput').value;
    if (!query.trim()) {
        showToast('Please enter a SQL query.', 'error');
        return;
    }

    logTerminal(`Executing Query: ${query}`, 'info');

    try {
        const res = await fetch('/api/execute-sql', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ query: query })
        });
        const data = await res.json();
        const container = document.getElementById('sqlResultContainer');
        const table = document.getElementById('sqlResultTable');

        if (data.success) {
            if (data.type === 'SELECT') {
                container.style.display = 'block';
                let thHtml = '<tr>' + data.columns.map(c => `<th>${c}</th>`).join('') + '</tr>';
                let trHtml = data.rows.map(r => '<tr>' + data.columns.map(c => `<td class="mono-cell">${r[c] !== null ? r[c] : 'NULL'}</td>`).join('') + '</tr>').join('');
                table.innerHTML = `<thead>${thHtml}</thead><tbody>${trHtml}</tbody>`;
                logTerminal(`✔ Fetched ${data.count} rows.`, 'success');
            } else {
                container.style.display = 'none';
                logTerminal(`✔ ${data.message}`, 'success');
                showToast(data.message, 'success');
                loadAllData();
            }
        } else {
            container.style.display = 'none';
            logTerminal(`[SQL ERROR] ${data.error}`, 'error');
            showToast(data.error, 'error');
        }
    } catch (e) {
        showToast(e.message, 'error');
    }
}

// ----------------------------------------------------------------------------
// UTILITIES (TERMINAL, TOAST, MODALS)
// ----------------------------------------------------------------------------
function logTerminal(msg, type = 'info') {
    const term = document.getElementById('dbmsTerminal');
    if (!term) return;
    const time = new Date().toLocaleTimeString();
    const line = document.createElement('div');
    line.className = `term-line-${type}`;
    line.innerText = `[${time}] ${msg}`;
    term.appendChild(line);
    term.scrollTop = term.scrollHeight;
}

function clearTerminal() {
    const term = document.getElementById('dbmsTerminal');
    if (term) term.innerHTML = '<div class="term-line-info">[CLEARED] Awaiting next procedure...</div>';
}

function showToast(msg, type = 'success') {
    const container = document.getElementById('toastContainer');
    if (!container) return;
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.innerText = msg;
    container.appendChild(toast);
    setTimeout(() => {
        toast.style.opacity = '0';
        setTimeout(() => toast.remove(), 300);
    }, 4500);
}

function setPresetRemark(inputId, text) {
    document.getElementById(inputId).value = text;
}

function filterTransactions() {
    const query = document.getElementById('txnSearch').value.toLowerCase();
    const filtered = state.transactions.filter(t => 
        (t.remarks && t.remarks.toLowerCase().includes(query)) ||
        (t.txn_type && t.txn_type.toLowerCase().includes(query)) ||
        t.txn_id.toString().includes(query)
    );
    renderTransactionsTable(filtered);
}

function openCreateAccountModal() { document.getElementById('modalCreateAccount').classList.add('open'); }
function openDepositModal() { document.getElementById('modalDeposit').classList.add('open'); }
function openWithdrawModal() { document.getElementById('modalWithdraw').classList.add('open'); }
function closeModal(id) { document.getElementById(id).classList.remove('open'); }

async function resetDatabase() {
    if (!confirm('Are you sure you want to reset the database to the 4 sample accounts?')) return;
    try {
        const res = await fetch('/api/reset', { method: 'POST' });
        const data = await res.json();
        if (data.success) {
            logTerminal('Database reset to initial schema and sample accounts.', 'info');
            showToast('Database reset successfully!', 'success');
            await loadAllData();
        }
    } catch (e) {
        showToast(e.message, 'error');
    }
}
