#!/usr/bin/env python3
"""RBAC Quest — interactive guided walkthrough of OpenShift AI access controls."""

import argparse
import atexit
import json
import signal
import subprocess
import sys
from datetime import datetime
from pathlib import Path

try:
    from rich.console import Console
    from rich.prompt import Prompt, Confirm
    from rich.table import Table
    from rich.panel import Panel
except ImportError:
    print("Error: 'rich' package required. Install: uv pip install rich")
    sys.exit(1)

console = Console()

PROGRESS_DIR = Path.home() / ".lumon"
PROGRESS_FILE = PROGRESS_DIR / "rbac-quest-progress"
QUEST_LABEL = "app.kubernetes.io/managed-by=lumon-quest"
APPLICATIONS_NS = "redhat-ods-applications"
OPERATOR_NS = "openshift-operators"
SCRIPT_DIR = Path(__file__).resolve().parent


# ── Cluster Interaction ──


def run_oc(*args):
    return subprocess.run(["oc"] + list(args), capture_output=True, text=True)


def can_i(verb, resource, namespace=None, as_user=None):
    cmd = ["oc", "auth", "can-i", verb, resource]
    if namespace:
        cmd.extend(["-n", namespace])
    if as_user:
        cmd.extend(["--as=" + as_user])
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.stdout.strip().lower() == "yes"


def cluster_health_gate():
    whoami = run_oc("whoami")
    if whoami.returncode != 0:
        console.print(Panel(
            "[red]Cluster is not accessible.[/red]\n\n"
            "Run [bold]bash scripts/smoke.sh[/bold] first to diagnose.",
            title="⚠️  Cluster Health Check Failed",
        ))
        sys.exit(1)

    dsc = run_oc(
        "get", "datascienceclusters", "default-dsc",
        "-o", "jsonpath={.status.phase}",
    )
    phase = dsc.stdout.strip()
    if phase != "Ready":
        console.print(Panel(
            f"[red]DataScienceCluster phase: {phase or 'not found'}[/red]\n\n"
            "Run [bold]bash scripts/smoke.sh[/bold] to diagnose.",
            title="⚠️  Cluster Health Check Failed",
        ))
        sys.exit(1)


# ── Progress Tracking ──


def _empty_progress():
    return {"mdr": {}, "od": {}, "certified": {}}


def load_progress():
    if PROGRESS_FILE.exists():
        try:
            return json.loads(PROGRESS_FILE.read_text())
        except (json.JSONDecodeError, OSError):
            pass
    return _empty_progress()


def save_progress(progress):
    PROGRESS_DIR.mkdir(parents=True, exist_ok=True)
    PROGRESS_FILE.write_text(json.dumps(progress, indent=2) + "\n")


def mark_level_complete(track, level_num):
    progress = load_progress()
    progress.setdefault(track, {})[str(level_num)] = {
        "completed": True,
        "timestamp": datetime.now().isoformat(),
    }
    save_progress(progress)


# ── Cleanup & Signals ──


def _exit_cleanup():
    pass


atexit.register(_exit_cleanup)
signal.signal(signal.SIGINT, lambda _s, _f: sys.exit(130))
signal.signal(signal.SIGTERM, lambda _s, _f: sys.exit(143))


# ── Quest Helpers ──


def wellness_checkpoint(question, choices, correct_key):
    console.print(f"\n[bold]Wellness Checkpoint[/bold]: {question}\n")
    for key, text in choices.items():
        console.print(f"  {key}) {text}")
    answer = Prompt.ask("\nYour answer", choices=list(choices.keys()))
    if answer == correct_key:
        console.print("[green]✅ Correct.[/green]\n")
        return True
    console.print(
        f"[yellow]→ The answer is {correct_key}) "
        f"{choices[correct_key]}[/yellow]\n"
    )
    return False


def display_checks(title, results):
    """Display results table. Each result: (desc, got_bool, expected_bool)."""
    table = Table(title=title)
    table.add_column("Check", style="cyan", no_wrap=False)
    table.add_column("Result", justify="center")
    table.add_column("Status", justify="center")
    for desc, got, expected in results:
        result_str = "[green]yes[/green]" if got else "[red]no[/red]"
        passed = got == expected
        status = "[green]PASS[/green]" if passed else "[red]FAIL[/red]"
        table.add_row(desc, result_str, status)
    console.print(table)
    console.print()
    return all(g == e for _, g, e in results)


def display_dry_run_checks(checks):
    table = Table(title="Planned Checks (dry-run)")
    table.add_column("Check", style="cyan", no_wrap=False)
    table.add_column("Command", style="dim")
    table.add_column("Expected", style="green")
    for c in checks:
        cmd = ["oc", "auth", "can-i", c["verb"], c["resource"]]
        if c.get("namespace"):
            cmd.extend(["-n", c["namespace"]])
        if c.get("as_user"):
            cmd.extend(["--as=" + c["as_user"]])
        table.add_row(
            c["desc"], " ".join(cmd),
            "allowed" if c["expect"] else "denied",
        )
    console.print(table)
    console.print()


def run_checks(checks):
    results = []
    for c in checks:
        got = can_i(
            c["verb"], c["resource"],
            namespace=c.get("namespace"),
            as_user=c.get("as_user"),
        )
        results.append((c["desc"], got, c["expect"]))
    return results


# ── MDR Track ──


def mdr_level_1(dry_run=False):
    console.print(Panel(
        "[bold]Trust Boundaries & Project Isolation[/bold]",
        title="MDR — Level 1",
        subtitle="The work is mysterious and important.",
    ))

    checks = [
        {"desc": "developer can create projects",
         "verb": "create", "resource": "projects",
         "as_user": "developer", "expect": True},
        {"desc": "developer cannot get nodes",
         "verb": "get", "resource": "nodes",
         "as_user": "developer", "expect": False},
        {"desc": "developer cannot get dscinitializations",
         "verb": "get", "resource": "dscinitializations",
         "as_user": "developer", "expect": False},
        {"desc": f"developer cannot list pods in {APPLICATIONS_NS}",
         "verb": "list", "resource": "pods",
         "namespace": APPLICATIONS_NS,
         "as_user": "developer", "expect": False},
        {"desc": f"developer cannot list pods in {OPERATOR_NS}",
         "verb": "list", "resource": "pods",
         "namespace": OPERATOR_NS,
         "as_user": "developer", "expect": False},
    ]

    if dry_run:
        display_dry_run_checks(checks)
        console.print(
            "[dim]Wellness: Why does namespace isolation matter "
            "in a regulated environment?[/dim]\n"
        )
        return True

    results = run_checks(checks)
    all_passed = display_checks("Trust Boundary Verification", results)

    wellness_checkpoint(
        "Why does namespace isolation matter in a regulated environment?",
        {"a": "It keeps the cluster tidy",
         "b": "It enforces data segregation between teams "
              "— a regulatory requirement",
         "c": "It makes deployments faster"},
        "b",
    )
    return all_passed


def mdr_level_2(dry_run=False):
    console.print(Panel(
        "[bold]Self-Service & Boundaries[/bold]",
        title="MDR — Level 2",
        subtitle="Every department has a purpose.",
    ))

    checks = [
        {"desc": "developer can create notebooks",
         "verb": "create", "resource": "notebooks.kubeflow.org",
         "as_user": "developer", "expect": True},
        {"desc": "developer can create PVCs",
         "verb": "create", "resource": "persistentvolumeclaims",
         "as_user": "developer", "expect": True},
        {"desc": "developer cannot patch odhdashboardconfigs",
         "verb": "patch", "resource": "odhdashboardconfigs",
         "namespace": APPLICATIONS_NS,
         "as_user": "developer", "expect": False},
        {"desc": "developer cannot patch datascienceclusters",
         "verb": "patch", "resource": "datascienceclusters",
         "as_user": "developer", "expect": False},
    ]

    if dry_run:
        display_dry_run_checks(checks)
        console.print(
            "[dim]Wellness: What breaks if a data scientist "
            "can modify groupsConfig?[/dim]\n"
        )
        return True

    results = run_checks(checks)
    all_passed = display_checks("Self-Service Verification", results)

    wellness_checkpoint(
        "What breaks if a data scientist can modify groupsConfig?",
        {"a": "Nothing — groupsConfig is read-only anyway",
         "b": "They could lock out their own team or grant "
              "admin access to everyone",
         "c": "The dashboard would crash"},
        "b",
    )
    return all_passed


def mdr_level_3(dry_run=False):
    console.print(Panel(
        "[bold]Model Serving Auth & Bug Hunt[/bold]",
        title="MDR — Level 3",
        subtitle="Your outie would be proud.",
    ))

    if dry_run:
        console.print(
            "[dim]1. Read odh-dashboard-config: "
            "disableKServeAuth (expect false)[/dim]"
        )
        console.print(
            "[dim]2. Check cross-namespace secret access for "
            "pipeline SA (expect denied)[/dim]"
        )
        console.print(
            "[dim]Wellness: A pipeline ServiceAccount can read "
            "secrets across all namespaces…[/dim]\n"
        )
        return True

    kserve_auth = run_oc(
        "get", "odhdashboardconfigs", "odh-dashboard-config",
        "-n", APPLICATIONS_NS,
        "-o", "jsonpath={.spec.dashboardConfig.disableKServeAuth}",
    ).stdout.strip()

    sa_can_read = can_i(
        "get", "secrets",
        namespace="other-ns",
        as_user="system:serviceaccount:test-ns:pipeline",
    )

    results = [
        ("disableKServeAuth is false",
         kserve_auth == "false", True),
        ("pipeline SA cannot read secrets cross-namespace",
         not sa_can_read, True),
    ]

    if sa_can_read:
        console.print(
            "[red bold]🐛 Bug found: pipeline SA has "
            "cross-namespace secret access![/red bold]\n"
        )

    all_passed = display_checks("Model Serving Auth", results)

    wellness_checkpoint(
        "A pipeline ServiceAccount can read secrets across all "
        "namespaces. What's the finding?",
        {"a": "This is normal for pipelines",
         "b": "Cross-namespace secret access — data breach risk, "
              "SOC 2 finding",
         "c": "ServiceAccounts don't have RBAC"},
        "b",
    )
    return all_passed


# ── O&D Track ──


def od_level_1(dry_run=False):
    console.print(Panel(
        "[bold]Operator Stewardship & Trust Boundaries[/bold]",
        title="O&D — Level 1",
        subtitle="Not everyone has the same clearance.",
    ))

    admin_checks = [
        {"desc": f"kubeadmin can get csv in {OPERATOR_NS}",
         "verb": "get", "resource": "csv",
         "namespace": OPERATOR_NS, "expect": True},
        {"desc": "kubeadmin can get datascienceclusters",
         "verb": "get", "resource": "datascienceclusters",
         "expect": True},
        {"desc": "kubeadmin can get dscinitializations",
         "verb": "get", "resource": "dscinitializations",
         "expect": True},
    ]

    dev_checks = [
        {"desc": f"developer cannot get csv in {OPERATOR_NS}",
         "verb": "get", "resource": "csv",
         "namespace": OPERATOR_NS,
         "as_user": "developer", "expect": False},
        {"desc": "developer cannot get datascienceclusters",
         "verb": "get", "resource": "datascienceclusters",
         "as_user": "developer", "expect": False},
        {"desc": "developer cannot get dscinitializations",
         "verb": "get", "resource": "dscinitializations",
         "as_user": "developer", "expect": False},
    ]

    if dry_run:
        display_dry_run_checks(admin_checks + dev_checks)
        console.print(
            "[dim]Wellness: Why must operator upgrades be "
            "performed as kubeadmin?[/dim]\n"
        )
        return True

    admin_results = run_checks(admin_checks)
    dev_results = run_checks(dev_checks)

    table = Table(title="Privilege Comparison: kubeadmin vs developer")
    table.add_column("Resource", style="cyan")
    table.add_column("kubeadmin", justify="center")
    table.add_column("developer", justify="center")
    table.add_column("Status", justify="center")

    resources = [
        f"get csv -n {OPERATOR_NS}",
        "get datascienceclusters",
        "get dscinitializations",
    ]
    all_passed = True
    for i, resource in enumerate(resources):
        a_got, a_exp = admin_results[i][1], admin_results[i][2]
        d_got, d_exp = dev_results[i][1], dev_results[i][2]
        a_str = "[green]yes[/green]" if a_got else "[red]no[/red]"
        d_str = "[green]yes[/green]" if d_got else "[red]no[/red]"
        ok = (a_got == a_exp) and (d_got == d_exp)
        if not ok:
            all_passed = False
        status = "[green]PASS[/green]" if ok else "[red]FAIL[/red]"
        table.add_row(resource, a_str, d_str, status)

    console.print(table)
    console.print()

    wellness_checkpoint(
        "Why must operator upgrades be performed as kubeadmin?",
        {"a": "kubeadmin has a better UI",
         "b": "Operator resources are cluster-scoped "
              "— namespace-scoped users cannot modify them",
         "c": "It's just a convention"},
        "b",
    )
    return all_passed


def od_level_2(dry_run=False):
    console.print(Panel(
        "[bold]Group Architecture & Division Management[/bold]",
        title="O&D — Level 2",
        subtitle="Departments are defined by their boundaries.",
    ))

    if dry_run:
        console.print(
            "[dim]1. Check if rhods-admins group exists: "
            "oc get group rhods-admins[/dim]"
        )
        console.print(
            "[dim]2. Read dashboard groupsConfig: "
            "adminGroups, allowedGroups[/dim]"
        )
        console.print(
            "[dim]Wellness: What happens if allowedGroups "
            "is changed?[/dim]\n"
        )
        return True

    group_result = run_oc("get", "group", "rhods-admins")
    group_exists = group_result.returncode == 0

    admin_groups = run_oc(
        "get", "odhdashboardconfigs", "odh-dashboard-config",
        "-n", APPLICATIONS_NS,
        "-o", "jsonpath={.spec.groupsConfig.adminGroups}",
    ).stdout.strip()

    allowed_groups = run_oc(
        "get", "odhdashboardconfigs", "odh-dashboard-config",
        "-n", APPLICATIONS_NS,
        "-o", "jsonpath={.spec.groupsConfig.allowedGroups}",
    ).stdout.strip()

    status = "exists ✅" if group_exists else "not found ⚠️"
    content = (
        f"[bold]rhods-admins group:[/bold] {status}\n"
        f"[bold]adminGroups:[/bold]       {admin_groups or '(not set)'}\n"
        f"[bold]allowedGroups:[/bold]     {allowed_groups or '(not set)'}"
    )
    console.print(Panel(content, title="Group Architecture"))

    if not group_exists:
        console.print(
            "[yellow]⚠️  rhods-admins group does not exist yet. "
            "Create it with: oc adm groups new rhods-admins[/yellow]\n"
        )

    wellness_checkpoint(
        "What happens if allowedGroups is changed from "
        "system:authenticated to rhods-admins?",
        {"a": "Only admins can log in — all data scientists "
              "lose dashboard access",
         "b": "Nothing changes",
         "c": "The dashboard requires a restart"},
        "a",
    )
    return True


def od_level_3(dry_run=False):
    console.print(Panel(
        "[bold]Cross-Division Sharing & ServiceAccount RBAC[/bold]",
        title="O&D — Level 3",
        subtitle="Trust is earned on the Severed Floor.",
    ))

    if dry_run:
        console.print(
            "[dim]1. Check modelregistry component management "
            "in DSC[/dim]"
        )
        console.print(
            "[dim]2. Verify pipeline SA is namespace-scoped "
            "(no cross-NS secret access)[/dim]"
        )
        console.print(
            "[dim]Wellness: What else is needed beyond "
            "namespace RBAC for isolation?[/dim]\n"
        )
        return True

    mr_state = run_oc(
        "get", "datascienceclusters", "default-dsc",
        "-o", "jsonpath={.spec.components.modelregistry.managementState}",
    ).stdout.strip()

    sa_can_read = can_i(
        "get", "secrets",
        namespace="other-ns",
        as_user="system:serviceaccount:test-ns:pipeline",
    )

    results = [
        ("modelregistry is Managed in DSC",
         mr_state.lower() == "managed", True),
        ("pipeline SA is namespace-scoped (no cross-NS secrets)",
         not sa_can_read, True),
    ]
    all_passed = display_checks("Cross-Division Verification", results)

    wellness_checkpoint(
        "Namespace RBAC alone does not provide network isolation. "
        "What else is needed?",
        {"a": "More namespaces",
         "b": "NetworkPolicy",
         "c": "A firewall appliance"},
        "b",
    )
    return all_passed


# ── Certification ──


CERT_WIDTH = 42


def certification(track, dry_run=False):
    if dry_run:
        console.print(
            "[dim]Certification: would run role-check.sh "
            "and display certificate.[/dim]\n"
        )
        return

    console.print(
        "\n[bold]The Board has reviewed your "
        "clearance application.[/bold]\n"
    )
    console.print("Running final RBAC parity validation…\n")

    role_check = subprocess.run(
        ["bash", str(SCRIPT_DIR / "role-check.sh")],
    )

    if role_check.returncode != 0:
        console.print(Panel(
            "[red]RBAC parity check did not pass.[/red]\n"
            "Resolve the issues above before certification.",
            title="Certification Denied",
        ))
        return

    track_labels = {"mdr": "MDR", "od": "O&D", "both": "Full Clearance"}
    track_label = track_labels[track]
    name = Prompt.ask(
        "\nThe Board requires your name for the certificate"
    )
    today = datetime.now().strftime("%Y-%m-%d")

    w = CERT_WIDTH
    name_line = f"  {name} has demonstrated"
    cert = "\n".join([
        "╔" + "═" * w + "╗",
        f"║{'DEPARTMENT CLEARANCE CERTIFICATE':^{w}s}║",
        f"║{'':<{w}s}║",
        f"║{'  The Board certifies that':<{w}s}║",
        f"║{name_line:<{w}s}║",
        f"║{'  adequate understanding of':<{w}s}║",
        f"║{'  Severed Floor access controls.':<{w}s}║",
        f"║{'':<{w}s}║",
        f"║{f'  Track: {track_label}':<{w}s}║",
        f"║{f'  Date:  {today}':<{w}s}║",
        f"║{'':<{w}s}║",
        f"║{'  Praise Kier.':<{w}s}║",
        "╚" + "═" * w + "╝",
    ])
    console.print(Panel(cert, title="🏆 Certification"))

    progress = load_progress()
    cert_entry = {"name": name, "date": today}
    progress.setdefault("certified", {})[track] = cert_entry
    if track == "both":
        progress["certified"]["mdr"] = cert_entry
        progress["certified"]["od"] = cert_entry
    save_progress(progress)


# ── --status ──


def show_status():
    progress = load_progress()

    table = Table(title="RBAC Quest Progress")
    table.add_column("Track", style="bold")
    table.add_column("Level 1", justify="center")
    table.add_column("Level 2", justify="center")
    table.add_column("Level 3", justify="center")
    table.add_column("Certified", justify="center")

    for track, label in [("mdr", "MDR"), ("od", "O&D")]:
        levels = progress.get(track, {})
        cols = []
        for lvl in ("1", "2", "3"):
            if levels.get(lvl, {}).get("completed"):
                cols.append("[green]✅[/green]")
            else:
                cols.append("[dim]—[/dim]")
        cert = progress.get("certified", {}).get(track)
        if cert:
            cols.append(f"[green]✅ {cert.get('date', '')}[/green]")
        else:
            cols.append("[dim]—[/dim]")
        table.add_row(label, *cols)

    console.print(table)

    full = progress.get("certified", {}).get("both")
    if full:
        console.print(
            f"\n[bold green]Full Clearance: ✅ "
            f"{full.get('date', '')}[/bold green]"
        )


# ── --cleanup ──


def do_cleanup():
    console.print("[bold]Cleaning up lumon-quest resources…[/bold]\n")
    result = run_oc(
        "delete", "all",
        "-l", QUEST_LABEL,
        "--all-namespaces",
    )
    if result.returncode == 0:
        console.print("[green]Cleanup complete.[/green]")
    else:
        output = (result.stderr or result.stdout).strip()
        if "No resources found" in output or not output:
            console.print(
                "[green]No quest resources found "
                "— nothing to clean up.[/green]"
            )
        else:
            console.print(f"[yellow]Cleanup returned: {output}[/yellow]")


# ── Orientation (Level 0) ──


def orientation():
    console.print(Panel(
        "[bold]Welcome to the RBAC Quest.[/bold]\n\n"
        "This guided walkthrough validates your understanding of\n"
        "OpenShift AI access controls on the Severed Floor.\n\n"
        "Before we begin, a brief orientation.",
        title="Orientation — Level 0",
    ))

    wellness_checkpoint(
        "In OpenShift AI, which two personas have fundamentally "
        "different privilege levels?",
        {"a": "Frontend developer and backend developer",
         "b": "Data scientist (namespace-scoped) and platform "
              "engineer (cluster-scoped)",
         "c": "QA engineer and release manager"},
        "b",
    )


# ── CLI ──


MDR_LEVELS = [mdr_level_1, mdr_level_2, mdr_level_3]
OD_LEVELS = [od_level_1, od_level_2, od_level_3]


def parse_args():
    parser = argparse.ArgumentParser(
        description="RBAC Quest — guided RBAC walkthrough for OpenShift AI",
    )
    parser.add_argument(
        "--persona", choices=["mdr", "od", "both"],
        help="Persona track to run (required for quest mode)",
    )
    parser.add_argument(
        "--level", type=int, choices=[1, 2, 3],
        help="Jump to a specific level",
    )
    parser.add_argument(
        "--status", action="store_true",
        help="Show completion state and exit",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Print planned commands without executing",
    )
    parser.add_argument(
        "--skip-orientation", action="store_true",
        help="Skip the Level 0 orientation quiz",
    )
    parser.add_argument(
        "--cleanup", action="store_true",
        help="Remove lumon-quest labeled resources and exit",
    )
    return parser.parse_args()


# ── Main ──


def main():
    args = parse_args()

    if args.status:
        show_status()
        return

    if args.cleanup:
        do_cleanup()
        return

    if not args.persona:
        console.print(
            "[red]--persona is required for quest mode. "
            "Choices: mdr, od, both[/red]"
        )
        sys.exit(1)

    if not args.skip_orientation and not args.level and not args.dry_run:
        orientation()

    tracks = []
    if args.persona in ("mdr", "both"):
        tracks.append(("mdr", MDR_LEVELS))
    if args.persona in ("od", "both"):
        tracks.append(("od", OD_LEVELS))

    for track_name, levels in tracks:
        start = (args.level or 1) - 1
        for i in range(start, len(levels)):
            if not args.dry_run:
                cluster_health_gate()
            levels[i](dry_run=args.dry_run)
            if not args.dry_run:
                mark_level_complete(track_name, i + 1)

    if not args.level:
        certification(args.persona, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
