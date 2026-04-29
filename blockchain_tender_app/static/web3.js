// web3.js — shared wallet/contract helpers for TenderCore

let contract;
let signer;

const CONTRACT_ADDRESS = "0x93d2E2885C3fBC1bb2c3a7c9Fc0A89dFc416673a"; // UPDATE after redeploy

const CONTRACT_ABI = [
  // ── Registration ──────────────────────────────────────────────────────
  "function requestRegistration(string,string,string,string)",
  "function approveUser(address)",
  "function rejectUser(address,string)",
  "function getPendingUsers() view returns (address[])",
  "function getProfile(address) view returns (string,string,string,string,string,uint8,uint256,uint256)",

  // ── Tender ────────────────────────────────────────────────────────────
  "function owner() view returns (address)",
  "function tenderCount() view returns (uint256)",
  // Returns: id, title, desc, biddingDeadline, votingDeadline, creator,
  //          highestBid, highestBidder, ended, totalVotes, winner
  "function tenders(uint256) view returns (uint256,string,string,uint256,uint256,address,uint256,address,bool,uint256,address)",
  "function getBidders(uint256) view returns (address[])",
  "function bids(uint256,address) view returns (uint256)",
  "function placeBid(uint256,uint256)",
  "function createTender(string,string,uint256,uint256)",

  // ── Voting ────────────────────────────────────────────────────────────
  "function castVote(uint256,address)",
  "function finalizeTender(uint256)",
  "function getVoteCounts(uint256) view returns (address[],uint256[])",
  "function getMyVote(uint256,address) view returns (address)",
  "function voteCount(uint256,address) view returns (uint256)",
];

async function connectWallet() {
  if (!window.ethereum) {
    alert("MetaMask not detected. Please install MetaMask.");
    throw new Error("MetaMask not detected");
  }
  await window.ethereum.request({ method: "eth_requestAccounts" });
  const provider = new ethers.BrowserProvider(window.ethereum);
  signer   = await provider.getSigner();
  contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);
  return contract;
}

// Used by register.html
async function requestRegistration() {
  try {
    await connectWallet();
    const fullName     = document.getElementById("fullName").value.trim();
    const organization = document.getElementById("organization").value.trim();
    const email        = document.getElementById("email").value.trim();
    const phone        = document.getElementById("phone").value.trim();

    if (!fullName || !organization) {
      alert("Please fill in Full Name and Organisation.");
      return;
    }
    const tx = await contract.requestRegistration(fullName, organization, email, phone);
    await tx.wait();
    alert("✅ Registration submitted. Awaiting admin approval.");
  } catch (err) {
    console.error(err);
    alert("❌ " + (err.reason || err.message || "Registration failed"));
  }
}
