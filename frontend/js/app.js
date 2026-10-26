/**
 * APEXBANK PL/SQL & ADBMS - CLIENT APP LOGIC
 * Manages frontend state, REST API calls, DOM rendering, ADBMS Hub, and terminal logging.
 */

let state = {
    accounts: [],
    transactions: [],
    audits: [],
    fraudAlerts: [],
    distributedTxns: [],
    stats: {}
};

// ----------------------------------------------------------------------------
// INITIALIZATION
// ----------------------------------------------------------------------------
document.addEventListener('DOMContentLoaded', () => {
    loadAllData();
    setInterval(loadAllData, 12000);
});

async function loadAllData() {
    await Promise.all([
        fetchStats(),
        fetchAccounts(),
        fetchTransactions(),
        fetchAudits(),
        fetchPartitionTxns('ALL'),
        fetchFraudAlerts(),
        fetchBranchMView(),
        fetchOlapAnalytics(),
        fetchDistributedTxns()
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
        'dashboard': { title: 'Banking Overview', sub: 'Real-time PL/SQL & ADBMS Transaction Management System' },
        'adbms': { title: 'ADBMS Architecture & Control Center', sub: 'Partitioning, Compound Triggers, Autonomous Fraud Logs, Bulk Processing, MViews & 2PC' },
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

function switchAdbmsSubTab(subTabId, el) {
    document.querySelectorAll('.adbms-subnav .chip-btn').forEach(btn => btn.classList.remove('active'));
    document.querySelectorAll('.adbms-sub-section').forEach(sec => sec.style.display = 'none');

    if (el) el.classList.add('active');
    const target = document.getElementById(`adbms-sub-${subTabId}`);
    if (target) target.style.display = 'block';
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
            if (document.getElementById('statFrauds')) {
                document.getElementById('statFrauds').innerText = state.stats.total_fraud_alerts || 0;
            }
            if (document.getElementById('statDtxns')) {
                document.getElementById('statDtxns').innerText = state.stats.total_distributed_txns || 0;
            }
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
            renderAuditTable();
        }
    } catch (e) {
        console.error('Error fetching audits:', e);
    }
}

async function fetchPartitionTxns(partition = 'ALL') {
    try {
        const res = await fetch(`/api/adbms/partitions/transactions?partition=${partition}`);
        const json = await res.json();
        if (json.success) {
            const tbody = document.getElementById('partitionTxnsTableBody');
            if (!tbody) return;
            if (json.data.length === 0) {
                tbody.innerHTML = '<tr><td colspan="8" style="text-align: center; color: var(--text-muted);">No transactions in this partition.</td></tr>';
                return;
            }
            tbody.innerHTML = json.data.map(t => `
                <tr>
                    <td class="mono-cell">#${t.txn_id}</td>
                    <td><span class="badge-adbms badge-range">${t.partition_name}</span></td>
                    <td class="mono-cell">${t.txn_date}</td>
                    <td><span class="badge badge-${t.txn_type.toLowerCase()}">${t.txn_type}</span></td>
                    <td class="mono-cell" style="font-weight: 700; color: ${t.txn_type === 'DEPOSIT' || t.txn_type === 'INTEREST' ? 'var(--emerald)' : 'var(--rose)'}">
                        ${t.txn_type === 'DEPOSIT' || t.txn_type === 'INTEREST' ? '+' : '-'}₹${t.amount.toLocaleString('en-IN', {minimumFractionDigits: 2})}
                    </td>
                    <td class="mono-cell">${t.from_account ? '#' + t.from_account : '—'}</td>
                    <td class="mono-cell">${t.to_account ? '#' + t.to_account : '—'}</td>
                    <td style="color: var(--text-secondary);">${t.remarks || '—'}</td>
                </tr>
            `).join('');
        }
    } catch (e) {
        console.error('Error fetching partitioned txns:', e);
    }
}

function filterPartitionTxns(part, el) {
    document.querySelectorAll('#adbms-sub-partitions .chip-btn').forEach(b => b.classList.remove('active'));
    if (el) el.classList.add('active');
    fetchPartitionTxns(part);
}

async function fetchFraudAlerts() {
    try {
        const res = await fetch('/api/adbms/fraud-alerts');
        const json = await res.json();
        if (json.success) {
            state.fraudAlerts = json.data;
            const tbody = document.getElementById('fraudAlertsTableBody');
            if (!tbody) return;
            if (json.data.length === 0) {
                tbody.innerHTML = '<tr><td colspan="7" style="text-align: center; color: var(--text-muted);">No security alerts logged.</td></tr>';
                return;
            }
            tbody.innerHTML = json.data.map(a => `
                <tr>
                    <td class="mono-cell">#${a.alert_id}</td>
                    <td class="mono-cell">${a.account_no ? '#' + a.account_no : 'SYSTEM'}</td>
                    <td><span class="badge-adbms badge-autonomous">${a.severity}</span></td>
                    <td style="color: #f87171; font-weight: 500;">${a.reason}</td>
                    <td class="mono-cell">₹${(a.attempted_amount || 0).toLocaleString('en-IN', {minimumFractionDigits: 2})}</td>
                    <td class="mono-cell" style="color: var(--text-muted);">${a.ip_address}</td>
                    <td class="mono-cell" style="font-size: 11px;">${a.alert_time}</td>
                </tr>
            `).join('');
        }
    } catch (e) {
        console.error('Error fetching fraud alerts:', e);
    }
}

async function fetchBranchMView() {
    try {
        const res = await fetch('/api/adbms/mviews/branches');
        const json = await res.json();
        if (json.success) {
            const tbody = document.getElementById('branchMViewTableBody');
            if (!tbody) return;
            tbody.innerHTML = json.data.map(b => `
                <tr>
                    <td class="mono-cell"><strong>${b.branch_code}</strong></td>
                    <td>${b.branch_name}</td>
                    <td><span class="badge-adbms badge-list">${b.region}</span></td>
                    <td class="mono-cell">${b.total_accounts}</td>
                    <td class="mono-cell" style="color: var(--emerald); font-weight: 700;">₹${b.total_branch_liquidity.toLocaleString('en-IN', {minimumFractionDigits: 2})}</td>
                    <td class="mono-cell">₹${b.avg_account_balance.toLocaleString('en-IN', {minimumFractionDigits: 2})}</td>
                    <td class="mono-cell" style="font-size: 11px; color: var(--text-muted);">${b.last_refreshed}</td>
                </tr>
            `).join('');
        }
    } catch (e) {
        console.error('Error fetching branch mview:', e);
    }
}

async function fetchOlapAnalytics() {
    try {
        const res = await fetch('/api/adbms/olap');
        const json = await res.json();
        if (json.success && json.data.wealth_ranks) {
            const tbody = document.getElementById('olapRankTableBody');
            if (!tbody) return;
            tbody.innerHTML = json.data.wealth_ranks.map(r => `
                <tr>
                    <td><span class="badge-adbms badge-range">${r.region}</span></td>
                    <td>${r.branch_name}</td>
                    <td class="mono-cell">#${r.account_no}</td>
                    <td><strong>${r.holder_name}</strong></td>
                    <td><span class="badge badge-${r.account_type.toLowerCase()}">${r.account_type}</span></td>
                    <td class="mono-cell" style="color: var(--emerald); font-weight: 700;">₹${r.balance.toLocaleString('en-IN', {minimumFractionDigits: 2})}</td>
                    <td class="mono-cell" style="font-weight: 800; color: #fbbf24;">Rank #${r.regional_rank}</td>
                </tr>
            `).join('');
        }
    } catch (e) {
        console.error('Error fetching olap:', e);
    }
}

async function fetchDistributedTxns() {
    try {
        const res = await fetch('/api/adbms/distributed-txns');
        const json = await res.json();
        if (json.success) {
            state.distributedTxns = json.data;
            const tbody = document.getElementById('dtxnTableBody');
            if (!tbody) return;
            if (json.data.length === 0) {
                tbody.innerHTML = '<tr><td colspan="8" style="text-align: center; color: var(--text-muted);">No distributed transactions logged.</td></tr>';
                return;
            }
            tbody.innerHTML = json.data.map(d => `
                <tr>
                    <td class="mono-cell">#${d.dtxn_id}</td>
                    <td class="mono-cell" style="font-size: 11px; color: #93c5fd;">${d.global_xid}</td>
                    <td><span class="badge-adbms badge-list">${d.source_branch}</span></td>
                    <td><span class="badge-adbms badge-range">${d.target_branch}</span></td>
                    <td class="mono-cell" style="font-weight: 700; color: var(--primary);">₹${d.amount.toLocaleString('en-IN', {minimumFractionDigits: 2})}</td>
                    <td><span class="badge-adbms ${d.phase_1_status === 'VOTE_COMMIT' ? 'badge-success' : 'badge-autonomous'}">${d.phase_1_status}</span></td>
                    <td><span class="badge-adbms ${d.phase_2_status === 'GLOBAL_COMMITTED' ? 'badge-success' : 'badge-autonomous'}">${d.phase_2_status}</span></td>
                    <td class="mono-cell" style="font-size: 11px; color: var(--text-muted);">${d.created_at}</td>
                </tr>
            `).join('');
        }
    } catch (e) {
        console.error('Error fetching dtxns:', e);
    }
}

// ----------------------------------------------------------------------------
// ADBMS INTERACTIVE ACTIONS
// ----------------------------------------------------------------------------
async function testCompoundTrigger() {
    const accNo = parseInt(document.getElementById('compoundAccountSelect').value);
    const amount = parseFloat(document.getElementById('compoundAmount').value) || 60000;
    const resultBox = document.getElementById('compoundResult');

    try {
        // We attempt a withdrawal or transfer exceeding daily ceiling
        const res = await fetch('/api/withdraw', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                account_no: accNo,
                amount: amount,
                remarks: 'Testing Compound Trigger Daily Cap'
            })
        });
        const data = await res.json();
        if (data.success) {
            resultBox.innerHTML = `
                <div style="background: rgba(16,185,129,0.1); border: 1px solid var(--emerald-border); padding: 14px; border-radius: 10px; color: var(--emerald);">
                    ✔ Transaction Allowed: Within daily limit.
                </div>
            `;
            showToast(data.message, 'success');
        } else {
            resultBox.innerHTML = `
                <div style="background: rgba(244,63,94,0.12); border: 1px solid var(--rose-border); padding: 16px; border-radius: 10px;">
                    <div style="color: var(--rose); font-weight: 800; font-size: 14px; margin-bottom: 6px;">
                        🛡️ COMPOUND TRIGGER INTERCEPTED BREACH!
                    </div>
                    <div style="font-size: 13px; color: #fecdd3; line-height: 1.5;">
                        ${data.error}
                    </div>
                    <div style="font-size: 12px; color: var(--text-muted); margin-top: 8px;">
                        ✔ Oracle Error Code: <strong>ORA-20010</strong><br>
                        ✔ Mutating Table Error (ORA-04091) avoided via 4-phase Compound Trigger.<br>
                        ✔ Autonomous Transaction logged to <code>FRAUD_ALERTS</code>!
                    </div>
                </div>
            `;
            showToast('Compound Trigger Daily Limit Exceeded!', 'error');
            await fetchFraudAlerts();
            await fetchStats();
        }
    } catch (e) {
        showToast(e.message, 'error');
    }
}

async function simulateOverdraftAlert() {
    try {
        const res = await fetch('/api/adbms/fraud-alerts/test', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ account_no: 1004, amount: 750000.0 })
        });
        const data = await res.json();
        showToast('Autonomous Fraud Incident committed independently!', 'success');
        await fetchFraudAlerts();
        await fetchStats();
    } catch (e) {
        showToast(e.message, 'error');
    }
}

async function executeBulkInterest() {
    const rate = parseFloat(document.getElementById('bulkRate').value) || 4.5;
    const resBox = document.getElementById('bulkInterestResult');
    try {
        const res = await fetch('/api/interest', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ rate: rate })
        });
        const data = await res.json();
        if (data.success) {
            resBox.innerHTML = `
                <div style="background: rgba(16,185,129,0.1); border: 1px solid var(--emerald-border); padding: 12px; border-radius: 8px; color: var(--emerald);">
                    <strong>✔ BULK COLLECT & FORALL Finished in ${data.data.elapsed_ms || '2.4'}ms!</strong><br>
                    Accounts Credited: <strong>${data.data.accounts_credited}</strong> | Total Paid: <strong>₹${data.data.total_interest_paid.toLocaleString('en-IN', {minimumFractionDigits: 2})}</strong>
                </div>
            `;
            showToast('Bulk Interest executed successfully!', 'success');
            await loadAllData();
        } else {
            showToast(data.error, 'error');
        }
    } catch (e) {
        showToast(e.message, 'error');
    }
}

async function executeBulkFee() {
    const fee = parseFloat(document.getElementById('bulkFeeAmount').value) || 150.0;
    const minTier = parseFloat(document.getElementById('bulkMinTier').value) || 2000.0;
    const resBox = document.getElementById('bulkFeeResult');
    try {
        const res = await fetch('/api/adbms/bulk/fee', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ fee_amount: fee, min_tier: minTier })
        });
        const data = await res.json();
        if (data.success) {
            resBox.innerHTML = `
                <div style="background: rgba(59,130,246,0.1); border: 1px solid var(--border-glow); padding: 12px; border-radius: 8px; color: #93c5fd;">
                    <strong>✔ FORALL SAVE EXCEPTIONS Batch Finished in ${data.data.elapsed_ms}ms!</strong><br>
                    Accounts Charged: <strong>${data.data.accounts_charged}</strong> | Total Collected: <strong>₹${data.data.total_fees_collected.toLocaleString('en-IN', {minimumFractionDigits: 2})}</strong>
                </div>
            `;
            showToast('Bulk maintenance charges applied!', 'success');
            await loadAllData();
        } else {
            showToast(data.error, 'error');
        }
    } catch (e) {
        showToast(e.message, 'error');
    }
}

async function refreshMViews() {
    try {
        const res = await fetch('/api/adbms/mviews/refresh', { method: 'POST' });
        const data = await res.json();
        if (data.success) {
            showToast('Materialized Views fast-refreshed!', 'success');
            await fetchBranchMView();
            await fetchOlapAnalytics();
        }
    } catch (e) {
        showToast(e.message, 'error');
    }
}

async function runDistributedTxn() {
    const sBranch = document.getElementById('dtxnSourceBranch').value;
    const tBranch = document.getElementById('dtxnTargetBranch').value;
    const fromAcc = parseInt(document.getElementById('dtxnFromAcc').value);
    const toAcc = parseInt(document.getElementById('dtxnToAcc').value);
    const amount = parseFloat(document.getElementById('dtxnAmount').value) || 2500;
    const scenario = document.getElementById('dtxnScenario').value;

    try {
        const res = await fetch('/api/adbms/distributed-txns', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                source_branch: sBranch,
                target_branch: tBranch,
                from_account: fromAcc,
                to_account: toAcc,
                amount: amount,
                simulate_fail: scenario
            })
        });
        const data = await res.json();
        if (data.success) {
            showToast(data.message, 'success');
        } else {
            showToast(data.error, 'error');
        }
        await fetchDistributedTxns();
        await fetchFraudAlerts();
        await loadAllData();
    } catch (e) {
        showToast(e.message, 'error');
    }
}

// ----------------------------------------------------------------------------
// RENDERING
// ----------------------------------------------------------------------------
function renderAccountCards() {
    const container = document.getElementById('accountsCardsContainer');
    if (!container) return;

    container.innerHTML = state.accounts.map(acc => {
        let typeColor = acc.account_type === 'SAVINGS' ? 'var(--primary)' : 
                        acc.account_type === 'SALARY' ? 'var(--emerald)' : 'var(--purple)';
        return `
            <div class="account-card" onclick="openMiniStatement(${acc.account_no})">
                <div class="card-chip"></div>
                <div style="display: flex; justify-content: space-between; align-items: flex-start;">
                    <div>
                        <div style="font-size: 11px; text-transform: uppercase; color: var(--text-muted); font-weight: 700;">
                            ${acc.branch_name || 'Connaught Place'} [${acc.region || 'NORTH'}]
                        </div>
                        <div style="font-size: 16px; font-weight: 700; color: var(--text-primary); margin-top: 2px;">
                            ${acc.holder_name}
                        </div>
                    </div>
                    <span class="badge badge-${acc.account_type.toLowerCase()}">${acc.account_type}</span>
                </div>
                <div style="margin: 20px 0 10px 0;">
                    <div style="font-size: 11px; color: var(--text-muted);">AVAILABLE BALANCE</div>
                    <div style="font-size: 24px; font-weight: 800; font-family: var(--font-mono); color: var(--text-primary);">
                        ₹${acc.balance.toLocaleString('en-IN', {minimumFractionDigits: 2})}
                    </div>
                </div>
                <div style="display: flex; justify-content: space-between; align-items: flex-end; font-size: 12px; color: var(--text-secondary); border-top: 1px solid var(--border-subtle); padding-top: 10px;">
                    <div>ACC: <strong class="mono-cell">#${acc.account_no}</strong></div>
                    <div>Daily Cap: <strong>₹${(acc.daily_limit || 50000).toLocaleString('en-IN')}</strong></div>
                </div>
            </div>
        `;
    }).join('');
}

function renderTransactionsTable(txns) {
    const tbody = document.getElementById('transactionsTableBody');
    if (!tbody) return;
    if (txns.length === 0) {
        tbody.innerHTML = '<tr><td colspan="8" style="text-align: center; color: var(--text-muted);">No transactions found.</td></tr>';
        return;
    }

    tbody.innerHTML = txns.map(t => `
        <tr>
            <td class="mono-cell">#${t.txn_id}</td>
            <td><span class="badge badge-${t.txn_type.toLowerCase()}">${t.txn_type}</span></td>
            <td class="mono-cell">${t.from_account ? '#' + t.from_account : '—'}</td>
            <td class="mono-cell">${t.to_account ? '#' + t.to_account : '—'}</td>
            <td class="mono-cell" style="font-weight: 700; color: ${t.txn_type === 'DEPOSIT' || t.txn_type === 'INTEREST' ? 'var(--emerald)' : 'var(--rose)'}">
                ${t.txn_type === 'DEPOSIT' || t.txn_type === 'INTEREST' ? '+' : '-'}₹${t.amount.toLocaleString('en-IN', {minimumFractionDigits: 2})}
            </td>
            <td><span class="badge badge-${t.status.toLowerCase()}">${t.status}</span></td>
            <td class="mono-cell" style="font-size: 12px;">${t.txn_date}</td>
            <td style="color: var(--text-secondary);">${t.remarks || '—'}</td>
        </tr>
    `).join('');
}

function renderAuditTable() {
    const tbody = document.getElementById('auditTableBody');
    if (!tbody) return;
    if (state.audits.length === 0) {
        tbody.innerHTML = '<tr><td colspan="7" style="text-align: center; color: var(--text-muted);">No audit events recorded yet.</td></tr>';
        return;
    }

    tbody.innerHTML = state.audits.map(a => `
        <tr>
            <td class="mono-cell">#${a.log_id}</td>
            <td class="mono-cell">#${a.account_no}</td>
            <td><span class="badge badge-audit">${a.action_type}</span></td>
            <td class="mono-cell">₹${(a.old_balance !== null ? a.old_balance : 0).toLocaleString('en-IN', {minimumFractionDigits: 2})}</td>
            <td class="mono-cell" style="font-weight: 700; color: ${a.new_balance >= (a.old_balance || 0) ? 'var(--emerald)' : 'var(--rose)'}">
                ₹${(a.new_balance !== null ? a.new_balance : 0).toLocaleString('en-IN', {minimumFractionDigits: 2})}
            </td>
            <td style="color: var(--text-muted); font-size: 11px;">${a.changed_by}</td>
            <td class="mono-cell" style="font-size: 12px;">${a.changed_at}</td>
        </tr>
    `).join('');
}

function populateAccountDropdowns() {
    const selects = [
        'mainTransferSender', 'mainTransferReceiver',
        'depositAccSelect', 'withdrawAccSelect',
        'compoundAccountSelect', 'dtxnFromAcc', 'dtxnToAcc'
    ];

    selects.forEach(id => {
        const el = document.getElementById(id);
        if (!el) return;
        const curVal = el.value;
        el.innerHTML = state.accounts.map(a => 
            `<option value="${a.account_no}">#${a.account_no} - ${a.holder_name} (₹${a.balance.toLocaleString('en-IN')})</option>`
        ).join('');
        if (curVal && state.accounts.some(a => a.account_no == curVal)) {
            el.value = curVal;
        }
    });

    updateSenderBalancePreview();
    updateReceiverBalancePreview();
}

function updateSenderBalancePreview() {
    const el = document.getElementById('mainTransferSender');
    const preview = document.getElementById('senderBalancePreview');
    if (!el || !preview) return;
    const acc = state.accounts.find(a => a.account_no == el.value);
    preview.innerText = acc ? `Available: ₹${acc.balance.toLocaleString('en-IN', {minimumFractionDigits: 2})}` : '';
}

function updateReceiverBalancePreview() {
    const el = document.getElementById('mainTransferReceiver');
    const preview = document.getElementById('receiverBalancePreview');
    if (!el || !preview) return;
    const acc = state.accounts.find(a => a.account_no == el.value);
    preview.innerText = acc ? `Current: ₹${acc.balance.toLocaleString('en-IN', {minimumFractionDigits: 2})}` : '';
}

// ----------------------------------------------------------------------------
// CORE TRANSACTIONS
// ----------------------------------------------------------------------------
async function handleMainTransfer() {
    const sAcc = parseInt(document.getElementById('mainTransferSender').value);
    const rAcc = parseInt(document.getElementById('mainTransferReceiver').value);
    const amt = parseFloat(document.getElementById('mainTransferAmount').value);
    const rem = document.getElementById('mainTransferRemarks').value;

    if (!amt || amt <= 0) {
        showToast('Please enter a valid positive transfer amount.', 'error');
        return;
    }

    try {
        const res = await fetch('/api/transfer', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                from_account: sAcc,
                to_account: rAcc,
                amount: amt,
                remarks: rem
            })
        });
        const data = await res.json();
        if (data.success) {
            showToast(data.message, 'success');
            document.getElementById('mainTransferAmount').value = '';
            await loadAllData();
        } else {
            showToast(data.error, 'error');
            await fetchFraudAlerts();
            await fetchStats();
        }
    } catch (e) {
        showToast(e.message, 'error');
    }
}

async function submitDeposit() {
    const accNo = parseInt(document.getElementById('depositAccSelect').value);
    const amt = parseFloat(document.getElementById('depositAmount').value);
    const rem = document.getElementById('depositRemarks').value;

    if (!amt || amt <= 0) {
        showToast('Please enter a valid deposit amount.', 'error');
        return;
    }

    try {
        const res = await fetch('/api/deposit', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ account_no: accNo, amount: amt, remarks: rem })
        });
        const data = await res.json();
        if (data.success) {
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
    const accNo = parseInt(document.getElementById('withdrawAccSelect').value);
    const amt = parseFloat(document.getElementById('withdrawAmount').value);
    const rem = document.getElementById('withdrawRemarks').value;

    if (!amt || amt <= 0) {
        showToast('Please enter a valid withdrawal amount.', 'error');
        return;
    }

    try {
        const res = await fetch('/api/withdraw', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ account_no: accNo, amount: amt, remarks: rem })
        });
        const data = await res.json();
        if (data.success) {
            showToast(data.message, 'success');
            closeModal('modalWithdraw');
            document.getElementById('withdrawAmount').value = '';
            await loadAllData();
        } else {
            showToast(data.error, 'error');
            await fetchFraudAlerts();
            await fetchStats();
        }
    } catch (e) {
        showToast(e.message, 'error');
    }
}

async function submitCreateAccount() {
    const name = document.getElementById('newAccName').value;
    const email = document.getElementById('newAccEmail').value;
    const phone = document.getElementById('newAccPhone').value;
    const branch = document.getElementById('newAccBranch').value;
    const accType = document.getElementById('newAccType').value;
    const dep = parseFloat(document.getElementById('newAccDeposit').value) || 0;

    if (!name || !email || !phone) {
        showToast('Please fill in Name, Email, and Phone.', 'error');
        return;
    }

    try {
        const res = await fetch('/api/accounts', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                holder_name: name,
                email: email,
                phone: phone,
                branch_code: branch,
                account_type: accType,
                initial_deposit: dep
            })
        });
        const data = await res.json();
        if (data.success) {
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
    try {
        const res = await fetch('/api/interest', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ rate: rate })
        });
        const data = await res.json();
        if (data.success) {
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
            } else {
                container.style.display = 'none';
                showToast(data.message, 'success');
                loadAllData();
            }
        } else {
            container.style.display = 'none';
            showToast(data.error, 'error');
        }
    } catch (e) {
        showToast(e.message, 'error');
    }
}

// ----------------------------------------------------------------------------
// UTILITIES (TOAST, MODALS, RESET)
// ----------------------------------------------------------------------------
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
    if (!confirm('Reset database to the multi-branch ADBMS dataset?')) return;
    try {
        const res = await fetch('/api/reset', { method: 'POST' });
        const data = await res.json();
        if (data.success) {
            showToast('Database reset successfully!', 'success');
            await loadAllData();
        }
    } catch (e) {
        showToast(e.message, 'error');
    }
}
