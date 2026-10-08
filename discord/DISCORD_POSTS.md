# Discord launch posts: Schlongburg Studios

Copy everything between the `---` lines. Each post is under Discord's 2,000-character limit. Fill in anything in [brackets].

---

## 1. #rules (also paste into Community rules screening)

---
**📜 Server Rules**

**1. Be respectful.** No harassment, hate speech, slurs or personal attacks. Disagreements are fine; insults aren't.
**2. No leaks or piracy.** Don't share, request or link leaked or cracked scripts, ours or anyone else's. Instant ban.
**3. No advertising.** Don't promote other servers, stores or services without staff permission. Share your own server only in #your-servers.
**4. Use the right channel.** Support questions go in support channels, not #general. Search #faq and #known-issues first.
**5. No DMing staff for support.** Use the forum or a ticket so others can benefit and nothing gets lost.
**6. No scams or suspicious links.** "Free Nitro," fake giveaways and shady downloads mean a ban.
**7. Follow Discord's Terms of Service** and Community Guidelines.

Staff decisions are final. Breaking the rules can lead to a warning, mute, kick or ban depending on severity.
---

## 2. #welcome / start-here

---
**👋 Welcome to Schlongburg Studios**

We build **FiveM police RP tools that actually work together.**

**Start here:**
🔹 **Chain of Command:** our free, open-source core for departments, ranks, divisions, callsigns and permissions. Set them up once and every compatible script uses them. → #chain-of-command
🔹 **Store:** paid scripts and resources → #store
🔹 **Need help?** Free core: #free-support · Paying customers: #create-ticket
🔹 **Ideas?** Drop them in #suggestions

**Supported frameworks:** QBCore and Qbox (ESX planned)

Grab your ping roles in **Channels & Roles** so you don't miss releases.
---

## 3. #faq (starter, add to it as questions come in)

---
**❓ Frequently Asked Questions**

**Is Chain of Command really free?**
Yes. It's MIT licensed, so you can use it on any server and even build paid scripts on top of it.

**Which frameworks are supported?**
QBCore and Qbox. ESX support is planned.

**What are the dependencies?**
`ox_lib` and `oxmysql`.

**My ranks aren't showing up. Why?**
Chain of Command reads ranks from your framework's job grades. Make sure the `job` and `grade` values in `config.lua` match your framework's jobs file exactly.

**Can I edit the paid scripts?**
Config and language files are always editable. Core logic is protected (escrowed) to prevent leaks.

**Do you offer refunds?**
Digital products aren't refundable after download unless they don't work as described and we can't fix it. Open a ticket and we'll make it right.

**How do I get the Verified Customer role?**
Open a ticket with your Tebex transaction ID.
---

## 4. #chain-of-command (pin this)

---
**⛓️ Chain of Command: Free Department Core**
**Current version:** v1.1.0 · **License:** MIT · **Frameworks:** QBCore, Qbox

**What it does**
Defines your departments, ranks, divisions, callsigns and permissions **once**. Every compatible police, EMS or DOJ script reads from it, so there's no more editing job names across ten resources.

✅ Multi-department (LSPD, BCSO, SAHP, EMS, DOJ, or anything you name)
✅ Rank-based permissions that flow down the chain of command
✅ Callsigns and divisions (Patrol, Detectives, SWAT, K9, FTO...)
✅ In-game roster: hire, fire, promote, demote with `/roster`
✅ Server-side permission checks and a full audit log
✅ Simple API for developers: `exports.cmd_chain:HasPermission(src, 'reports.approve')`

🆕 **New in v1.1: in-game rank editor**
Build your rank structure without touching a file. Open `/ranks` to add as many ranks as you need, rename them, set pay and choose permissions. Changes are saved, and your framework's job grades are created for you.
🔒 Server owners can edit every rank. Chiefs can edit only the ranks below them and can't give out powers they don't have.

**Get it**
📦 Download: [GitHub release link]
📖 Install guide (5 minutes): [README link]
🧑‍💻 Developer API docs: [API docs link]

**Need help?** Post in #free-support with your framework, the version, and your error from the server console.
---

## 5. Ticket Tool opening message

---
**🎫 Support Ticket**

Thanks for reaching out! To help us fix this fast, please reply with:

1️⃣ **Product** and version
2️⃣ **Tebex transaction ID** (paid products)
3️⃣ **Framework:** QBCore or Qbox, and its version
4️⃣ **What happened** vs what you expected
5️⃣ **Errors:** server console and F8 client console (screenshots or text)
6️⃣ **What you've tried** so far

We usually respond within [24 hours]. Please don't ping staff. We'll get to you as soon as we can.
---

## 6. #roadmap (first post)

---
**🗺️ Roadmap**

**✅ Now**
⛓️ **Chain of Command v1:** free department core (QBCore and Qbox)
📄 **Police Department Starter Docs:** SOP manual, penal code, training program, rank structure, Discord template

**🔨 Next**
🚓 **Police MDT Suite** built on Chain of Command: reports, records, warrants, roster and pay management in one place

**💭 Later (vote in #suggestions)**
🚑 EMS and Fire suite · ⚖️ DOJ and court system · 🚨 Integrated dispatch · 🌍 Translations (Portuguese, Thai, German, Arabic) · ESX support

Everything we build plugs into Chain of Command, so it all works together out of the box.
---
