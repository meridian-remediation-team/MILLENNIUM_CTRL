# MILLENNIUM_CTRL — Global Y2K Remediation Coordination Project

**Status:** ACTIVE  
**Classification:** INTERNAL — DO NOT DISTRIBUTE  
**Maintainer:** meridian-ops  
**Last updated:** see commit log  

---

## What is this

This repository coordinates patch distribution for the global Y2K remediation effort.
We are tracking known-vulnerable systems across financial, infrastructure, and
telecommunications clusters and distributing fixes as fast as we can build them.

If you are reading this and you are not part of the team: this is not the place
you are looking for. The public-facing status page is elsewhere.

If you are part of the team: pull before you push. Every hour counts.
The shared deploy script is `deploy_patch.sh`. Do not modify it without
going through cole first.

---

## Scope

We are responsible for the following cluster types:

- **Financial systems** — COBOL batch runners, interest calculation subroutines,
  invoice generation. Most of the damage is buried in legacy fincore shared libraries
  that have not been touched since the mid-1980s.

- **Infrastructure** — SunOS and AIX nodes running date-sensitive cron jobs,
  log rotation, and backup scheduling. Surprisingly bad. The sysadmins who set
  these up in 1988 are mostly retired or unreachable.

- **Telecom routing** — The routing table timestamp format issue. If you are new
  to this problem, read `docs/tel_routing_issue.txt` before touching anything.

---

## Repository structure

```
/
├── README.md                  (this file)
├── deploy_patch.sh            (automated patch deployer — run this)
├── verify_rollover.sh         (verification suite — run this after deploying)
├── verify_rollover_legacy.sh  (kept for compatibility reasons)
├── scan_dates.pl              (deep scanner for 2-digit year patterns)
├── cobol/
│   ├── patch_banking.cob      (interest calculation fix — fincore dependency)
│   └── date_rollover.cob      (generic date comparison fix)
├── c/
│   ├── sysdate_fix.c          (SunOS/AIX sysdate wrapper)
│   └── epoch_calc.h           (utility header — do not use stdlib date functions)
├── asm/
│   └── bios_hook.asm          (BIOS date hook override — last resort only)
└── docs/
    └── tel_routing_issue.txt  (telecom timestamp format problem — read first)
```

---

## Critical known issues

1. **fincore.so** — `CALC_INTEREST_YR` and `DATE_COMPARE` use 2-digit year fields
   on lines 2201, 4455, 4456. The patch in `cobol/patch_banking.cob` addresses this
   but requires a full relink of the shared library. Do not hot-patch in production
   without isolating the node first.

2. **billrun** — The invoice date generation in `/opt/billing/billrun` will overflow
   at rollover. Patch is in `cobol/date_rollover.cob`. This one is time-critical.
   billrun runs automatically at 00:00:00. If the node is not patched before midnight
   it will abort mid-batch. Coordinate with the financial team before deploying.

3. **IBM mainframe firmware** — BIOS hook date table hard-coded to 1999. The fix
   in `asm/bios_hook.asm` is a last resort. Requires a full firmware flash.
   Do not attempt without authorization and a minimum 6-hour window.

4. **SunOS nodes below 4.1.2** — The automated patcher (`deploy_patch.sh`) does
   not support these. Manual intervention required. See `c/sysdate_fix.c`.

---

## How to deploy

```bash
# Dry run first. Always.
./verify_rollover.sh --cluster=EAST --dry-run

# Deploy to specific nodes
./deploy_patch.sh --cluster=EAST --nodes=EAST-FIN-01,EAST-FIN-02

# Full cluster (use --force only if time is critical and you accept the risk)
./deploy_patch.sh --cluster=WEST --force

# Deep scan for missed vulnerabilities
./scan_dates.pl --deep --target=WEST-FIN-*
```

---

## Contact

If something breaks: tty2 or tty5 at the Meridian terminal.  
If nobody answers: you're on your own. Sorry.

---

*"We built these systems to last. We just didn't think about what 'last' meant."*
