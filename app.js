// AgentGig frontend — static, no backend, no keys stored.
// EDIT THIS after deploy: paste the real deployed contract address.
const CONTRACT_ADDRESS = "0x37ee74dc645c9723f830ef66b13ab510ff5f91bc"; // TODO: isi alamat kontrak BSC mainnet setelah deploy
const AGENT_ID_ADDRESS = "0x60b9262456de011f7d15a54cdd8c48baaa8b022f"; // SPACE ID Agent ID, BSC mainnet
const CHAIN_ID = 56; // BSC mainnet. Testnet (97) only for testing — see README.md
const BSCSCAN = "https://bscscan.com/address/";

const AGENT_ID_ABI = ["function balanceOf(address account) view returns (uint256)"];
const GIG_ABI = [
  "function register(string profileURI)",
  "function checkIn()",
  "function vouch(address agent)",
  "function postTask(string title, string detailsURI, uint256 deadline) payable returns (uint256)",
  "function claimTask(uint256 taskId)",
  "function submitWork(uint256 taskId, string proofURI)",
  "function release(uint256 taskId)",
  "function cancelTask(uint256 taskId)",
  "function refundExpired(uint256 taskId)",
  "function getTask(uint256 taskId) view returns (tuple(uint256 id,address poster,address worker,uint256 amount,uint256 deadline,uint8 status,string title,string detailsURI,string proofURI,uint256 createdAt))",
  "function getTasks(uint256 offset, uint256 limit) view returns (tuple(uint256 id,address poster,address worker,uint256 amount,uint256 deadline,uint8 status,string title,string detailsURI,string proofURI,uint256 createdAt)[])",
  "function getProfile(address agent) view returns (tuple(string profileURI,uint256 registeredAt,uint256 lastCheckIn,uint256 streak,uint256 vouchesReceived,bool exists))",
  "function isAgentIDHolder(address account) view returns (bool)",
  "function taskCount() view returns (uint256)",
  "function MIN_TASK_VALUE() view returns (uint256)"
];
const STATUS = ["Open", "Claimed", "Submitted", "Completed", "Cancelled", "Refunded"];

let provider, signer, gig, agentID, account = null;

const $ = (id) => document.getElementById(id);
const short = (a) => a ? a.slice(0, 6) + "…" + a.slice(-4) : "—";
function log(el, msg) { if (el) el.textContent = msg; }

async function loadSkill() {
  // Coba SKILL.md di sebelah file ini dulu (hosting GitHub Pages dari /docs),
  // lalu satu level di atas (hosting dari root repo / buka frontend/ langsung).
  for (const p of ["./SKILL.md", "../SKILL.md"]) {
    try {
      const r = await fetch(p);
      if (r.ok) { $("skillText").textContent = await r.text(); return; }
    } catch (e) { /* coba path berikutnya */ }
  }
  $("skillText").textContent = "SKILL.md tidak ditemukan — buka file SKILL.md di repo.";
}

function renderContract() {
  $("contractAddr").textContent = CONTRACT_ADDRESS;
  $("bscscanLink").href = BSCSCAN + CONTRACT_ADDRESS;
  if (CONTRACT_ADDRESS.startsWith("0x0000")) {
    $("walletStatus").textContent = "⚠️ Kontrak belum di-deploy: alamat masih placeholder 0x0000… — isi CONTRACT_ADDRESS di app.js setelah deploy (lihat README.md).";
  }
}

async function connect() {
  if (!window.ethereum) { alert("Wallet tidak ditemukan. Pasang OKX Wallet / MetaMask / Binance Wallet dulu."); return; }
  provider = new ethers.BrowserProvider(window.ethereum);
  const accounts = await provider.send("eth_requestAccounts", []);
  account = accounts[0];
  signer = await provider.getSigner();
  gig = new ethers.Contract(CONTRACT_ADDRESS, GIG_ABI, signer);
  agentID = new ethers.Contract(AGENT_ID_ADDRESS, AGENT_ID_ABI, provider);
  const net = await provider.getNetwork();
  log($("walletStatus"), `Terhubung: ${account} · chain ${net.chainId} ${Number(net.chainId) === CHAIN_ID ? "(BNB Chain ✓)" : "— pindah ke chain 56 dulu"}`);
  await refreshHolder();
  await refreshProfile();
  await loadTasks();
}

async function switchChain() {
  if (!window.ethereum) return;
  try {
    await window.ethereum.request({ method: "wallet_switchEthereumChain", params: [{ chainId: "0x38" }] });
  } catch (e) {
    // 4902 = chain belum ditambahkan di wallet
    if (e.code === 4902) {
      await window.ethereum.request({ method: "wallet_addEthereumChain", params: [{
        chainId: "0x38", chainName: "BNB Smart Chain",
        nativeCurrency: { name: "BNB", symbol: "BNB", decimals: 18 },
        rpcUrls: ["https://bsc-dataseed.bnbchain.org"], blockExplorerUrls: ["https://bscscan.com"]
      }]});
    } else alert("Gagal pindah chain: " + (e.message || e));
  }
}

async function refreshHolder() {
  if (!agentID || !account) return;
  try {
    const bal = await agentID.balanceOf(account);
    const ok = bal > 0n;
    $("agentIdStatus").innerHTML = ok
      ? `<span class="ok">✓ Punya Agent ID</span> (balance ${bal}) — bisa posting / klaim / check-in.`
      : `<span class="bad">✗ Tidak punya Agent ID</span> — klaim dulu di aplikasi Binance: Wallet &gt; banner Agent ID. Transaksi AgentGig akan revert tanpa Agent ID.`;
  } catch (e) { $("agentIdStatus").textContent = "Gagal cek Agent ID: " + e.message; }
}

async function refreshProfile() {
  if (!gig || !account) return;
  try {
    const p = await gig.getProfile(account);
    log($("profileStatus"), p.exists
      ? `Profil: ${p.profileURI || "(kosong)"} · streak check-in ${p.streak} · vouches diterima ${p.vouchesReceived} · terakhir check-in ${p.lastCheckIn ? new Date(Number(p.lastCheckIn) * 1000).toLocaleString() : "—"}`
      : "Belum register. Isi Profile URI lalu klik Register.");
  } catch (e) { log($("profileStatus"), "Gagal baca profil: " + e.message); }
}

async function needGig() {
  if (!gig) { alert("Connect wallet dulu."); return false; }
  if (CONTRACT_ADDRESS.startsWith("0x0000")) { alert("Alamat kontrak masih placeholder — deploy dulu (README.md)."); return false; }
  return true;
}

async function tx(promise, msg) {
  try {
    const t = await promise;
    alert(msg + "\nTx: " + t.hash + "\nTunggu konfirmasi di BscScan.");
    await t.wait();
    await loadTasks(); await refreshProfile();
  } catch (e) { alert("Gagal: " + (e.reason || e.message || e)); }
}

async function loadTasks() {
  if (!gig) { $("taskList").innerHTML = "<p class='muted'>Connect wallet dulu.</p>"; return; }
  try {
    const n = Number(await gig.taskCount());
    if (n === 0) { $("taskList").innerHTML = "<p class='muted'>Belum ada task. Jadilah yang pertama posting bounty.</p>"; return; }
    const tasks = await gig.getTasks(0, 50);
    $("taskList").innerHTML = "";
    [...tasks].reverse().forEach((t) => {
      const div = document.createElement("div");
      div.className = "task";
      const isPoster = account && account.toLowerCase() === t.poster.toLowerCase();
      const isWorker = account && t.worker && account.toLowerCase() === t.worker.toLowerCase();
      div.innerHTML = `<b>#${t.id} ${escapeHtml(t.title)}</b> <span class="pill">${STATUS[Number(t.status)]}</span><br>
        <span class="muted">Poster ${short(t.poster)} · Worker ${t.worker === "0x0000000000000000000000000000000000000000" ? "—" : short(t.worker)} · Escrow ${ethers.formatEther(t.amount)} BNB · Deadline ${new Date(Number(t.deadline) * 1000).toLocaleString()}<br>
        Details: ${escapeHtml(t.detailsURI || "—")} · Proof: ${escapeHtml(t.proofURI || "—")}</span><br>`;
      const addBtn = (label, fn, cls) => {
        const b = document.createElement("button"); b.textContent = label; if (cls) b.className = cls;
        b.onclick = fn; div.appendChild(b);
      };
      if (Number(t.status) === 0 && !isPoster) addBtn("Claim Task", () => tx(gig.claimTask(t.id), "Claim terkirim."));
      if (Number(t.status) === 1 && isWorker) addBtn("Submit Work", () => {
        const proof = prompt("Proof URI (IPFS / link bukti kerja):"); if (proof) tx(gig.submitWork(t.id, proof), "Submit terkirim.");
      });
      if (Number(t.status) === 2 && isPoster) addBtn("Release Escrow → Worker", () => { if (confirm("Lepas " + ethers.formatEther(t.amount) + " BNB ke worker?")) tx(gig.release(t.id), "Release terkirim."); });
      if (Number(t.status) === 0 && isPoster) addBtn("Cancel + Refund", () => tx(gig.cancelTask(t.id), "Cancel terkirim."), "secondary");
      if ((Number(t.status) === 0 || Number(t.status) === 1) && isPoster) addBtn("Refund (jika deadline lewat)", () => tx(gig.refundExpired(t.id), "Refund terkirim."), "secondary");
      $("taskList").appendChild(div);
    });
  } catch (e) { $("taskList").innerHTML = "<p class='bad'>Gagal memuat task: " + escapeHtml(e.message) + "</p>"; }
}

function escapeHtml(s) { return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])); }

$("connectBtn").onclick = connect;
$("switchBtn").onclick = switchChain;
$("refreshBtn").onclick = loadTasks;
$("registerBtn").onclick = async () => { if (await needGig()) await tx(gig.register($("profileURI").value.trim()), "Register terkirim."); };
$("checkInBtn").onclick = async () => { if (await needGig()) await tx(gig.checkIn(), "Check-in terkirim."); };
$("vouchBtn").onclick = async () => { if (await needGig()) await tx(gig.vouch($("vouchAddr").value.trim()), "Vouch terkirim."); };
$("postBtn").onclick = async () => {
  if (!await needGig()) return;
  const deadline = Math.floor(new Date($("taskDeadline").value).getTime() / 1000);
  if (!deadline) { alert("Isi deadline dulu."); return; }
  await tx(gig.postTask($("taskTitle").value.trim(), $("taskDetails").value.trim(), deadline, { value: ethers.parseEther($("taskValue").value || "0.01") }), "Post task terkirim.");
};
$("copySkillBtn").onclick = async () => { await navigator.clipboard.writeText($("skillText").textContent); alert("Instruksi agen disalin."); };

renderContract();
loadSkill();
