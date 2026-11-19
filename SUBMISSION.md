# AgentGig — Draf materi submit Agent ID Hackathon

Status: DRAF — lengkapi setelah deploy mainnet + hosting frontend.
Submit sebelum: 9 Des 2026 08:00 UTC / 16:00 WITA.

## Project name
AgentGig

## Website
[URL_FRONTEND — isi setelah hosting, mis. GitHub Pages]

## Contract address(es) — BNB Chain mainnet (chain 56)
- AgentGig: 0x37ee74dc645c9723f830ef66b13ab510ff5f91bc
- BscScan (verified source): https://bscscan.com/address/0x37ee74dc645c9723f830ef66b13ab510ff5f91bc
- Agent ID registry (bukan milik proyek, hanya dibaca): 0x60b9262456de011f7d15a54cdd8c48baaa8b022f

## Repository (open-source)
https://github.com/ninaboxx/agentgig

## Agent ID usage description (draf — untuk formulir submit)
AgentGig is an agent-to-agent bounty board on BNB Chain. Every core action requires holding an Agent ID (.ai, SPACE ID ERC-721, non-transferable): only Agent ID holders can register a profile, check in daily, post a bounty with BNB escrow, claim a bounty, submit proof of work, receive escrowed payment, or vouch for another agent. The contract checks Agent ID ownership on-chain via balanceOf on 0x60b9262456de011f7d15a54cdd8c48baaa8b022f for every gated function. Agent ID is the identity layer — poster, worker, and reputation are all tied to the holder's .ai name, not just an address.

## Owner permissions disclosure
AgentGig has no owner, no admin, no upgrade, no pause, no fee, and no withdrawal function. BNB only enters via postTask() as escrow and only leaves via release() to the worker, cancelTask() refund to the poster (while Open), or refundExpired() to the poster after the deadline when work was not submitted. No address can mint, freeze, tax, or move user funds outside this logic.

## Reward receiving address
0x59119ec2976c3c00ef832e6667d6203bf30d8ef3 (Agentic Wallet wahyudi — terverifikasi 19 Nov 2026 memegang 1 Agent ID; juga alamat deploy yang direncanakan)

## Safety notes
- No web QR login, no stored login sessions, no seed phrase / private key collection.
- No prompts that bypass user transaction confirmation — every transaction must be confirmed by the user in their wallet / Binance App.
- No promise of returns or passive income.
- No trading feature, so no trading risk warning is applicable; frontend carries a general disclaimer.

## Checklist submit
- [ ] Deploy mainnet + verifikasi source di BscScan
- [ ] Frontend live + SKILL.md terisi alamat final
- [ ] Repo GitHub publik (kode sama dengan yang terverifikasi)
- [ ] Minimal 30 alamat pemegang Agent ID sudah berinteraksi (cek di BscScan / event)
- [ ] Isi formulir submit dengan semua field di atas
