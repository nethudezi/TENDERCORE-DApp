// admin.js — standalone fallback script (legacy)
// NOTE: admin.html already contains its own inline JS with full functionality.
// This file is kept for import compatibility but the core logic lives in admin.html.

// These functions are defined here so any HTML that imports admin.js separately
// can still call them. They delegate to the inline contract/signer globals.

async function loadPendingUsers() {
  const container = document.getElementById("pendingList");
  if (!container) return; // guard — element may not exist on all pages
  container.innerHTML = "Loading…";

  try {
    await connectWallet();

    const owner = await contract.owner();
    const me    = await signer.getAddress();

    if (owner.toLowerCase() !== me.toLowerCase()) {
      container.innerHTML = `
        <div class="adm-alert al-e show">
          ❌ Not admin. Connect the OWNER wallet.<br>
          <b>Owner:</b> ${owner}<br>
          <b>You:</b> ${me}
        </div>`;
      return;
    }

    const users = await contract.getPendingUsers();
    container.innerHTML = `<div class="t2 mono" style="font-size:.75rem;margin-bottom:.75rem;">Pending queue: ${users.length}</div>`;

    let pendingFound = false;

    for (const userAddr of users) {
      const profile = await contract.getProfile(userAddr);
      const status  = Number(profile[5]); // uint8 RegStatus

      if (status === 1) { // Pending
        pendingFound = true;
        container.innerHTML += `
          <div class="user-card">
            <div class="u-av" style="background:linear-gradient(135deg,var(--amber),var(--orange));">
              ${(profile[0]||'?')[0].toUpperCase()}
            </div>
            <div class="u-info">
              <div class="u-name">${esc(profile[0])}</div>
              <div class="u-addr">${userAddr}</div>
              <div class="u-meta">${esc(profile[1])} · ${esc(profile[4])}</div>
            </div>
            <div class="u-actions">
              <span class="badge b-pending">Pending</span>
              <button class="btn-ok" onclick="approveUser('${userAddr}')"><i class="fas fa-check"></i> Approve</button>
              <button class="btn-no" onclick="rejectUserPrompt('${userAddr}')"><i class="fas fa-times"></i> Reject</button>
            </div>
          </div>`;
      }
    }

    if (!pendingFound) {
      container.innerHTML += `<div class="empty"><div class="empty-i">👤</div><div class="empty-t">No pending requests.</div></div>`;
    }

  } catch (err) {
    console.error(err);
    if (container) {
      container.innerHTML = `<div class="adm-alert al-e show">❌ ${err.reason || err.message}</div>`;
    }
  }
}

async function approveUser(userAddr) {
  try {
    const tx = await contract.approveUser(userAddr);
    await tx.wait();
    alert("✅ Approved");
    loadPendingUsers();
  } catch (err) {
    alert("❌ " + (err.reason || err.message));
  }
}

async function rejectUserPrompt(userAddr) {
  const reason = prompt("Rejection reason:", "Not eligible");
  if (reason === null) return;
  try {
    const tx = await contract.rejectUser(userAddr, reason);
    await tx.wait();
    alert("✅ Rejected");
    loadPendingUsers();
  } catch (err) {
    alert("❌ " + (err.reason || err.message));
  }
}

function esc(s) {
  return String(s || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
