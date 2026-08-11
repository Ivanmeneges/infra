#!/usr/bin/env python3
"""Generate branded MOSIP self-service deployment KT PowerPoint with flow diagrams."""

from __future__ import annotations

from pathlib import Path

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_CONNECTOR, MSO_SHAPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.util import Inches, Pt, Emu

HERE = Path(__file__).resolve().parent
OUT = HERE / "MOSIP_New_Environment_Deployment_KT.pptx"
LOGO = HERE / "mosip_logo.png"
SVG_LOGO = HERE.parent / "_images" / "MOSIP_Black.svg"


def ensure_logo() -> None:
    if LOGO.exists():
        return
    if not SVG_LOGO.exists():
        return
    try:
        import cairosvg

        cairosvg.svg2png(url=str(SVG_LOGO), write_to=str(LOGO), output_width=400)
    except Exception:
        pass

# MOSIP-inspired palette
NAVY = RGBColor(0x0B, 0x1F, 0x3A)
TEAL = RGBColor(0x00, 0x96, 0xC7)
SKY = RGBColor(0x4D, 0xBD, 0xE5)
ORANGE = RGBColor(0xF5, 0x7C, 0x00)
GREEN = RGBColor(0x2E, 0x7D, 0x32)
PURPLE = RGBColor(0x5E, 0x35, 0xB1)
BODY = RGBColor(0x2D, 0x34, 0x40)
MUTED = RGBColor(0x5C, 0x67, 0x7D)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)
LIGHT_BG = RGBColor(0xF0, 0xF6, 0xFA)
HEADER_BG = RGBColor(0xE8, 0xF4, 0xFA)


def notes(slide, text: str) -> None:
    slide.notes_slide.notes_text_frame.text = text.strip()


def fill_shape(shape, color: RGBColor, line: RGBColor | None = None) -> None:
    shape.fill.solid()
    shape.fill.fore_color.rgb = color
    if line:
        shape.line.color.rgb = line
        shape.line.width = Pt(1)
    else:
        shape.line.fill.background()


def set_text(
    shape,
    text: str,
    *,
    size: int = 14,
    bold: bool = False,
    color: RGBColor = BODY,
    align=PP_ALIGN.CENTER,
) -> None:
    tf = shape.text_frame
    tf.clear()
    tf.word_wrap = True
    tf.vertical_anchor = MSO_ANCHOR.MIDDLE
    p = tf.paragraphs[0]
    p.text = text
    p.font.size = Pt(size)
    p.font.bold = bold
    p.font.color.rgb = color
    p.alignment = align


def add_header_bar(slide, title: str, subtitle: str | None = None) -> None:
    bar = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, Inches(10), Inches(1.05))
    fill_shape(bar, NAVY)
    bar.line.fill.background()

    title_box = slide.shapes.add_textbox(Inches(0.45), Inches(0.15), Inches(7.5), Inches(0.55))
    set_text(title_box, title, size=26, bold=True, color=WHITE, align=PP_ALIGN.LEFT)

    if subtitle:
        sub_box = slide.shapes.add_textbox(Inches(0.45), Inches(0.62), Inches(8.5), Inches(0.35))
        set_text(sub_box, subtitle, size=12, color=SKY, align=PP_ALIGN.LEFT)

    if LOGO.exists():
        slide.shapes.add_picture(str(LOGO), Inches(8.55), Inches(0.18), height=Inches(0.7))

    accent = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, Inches(1.05), Inches(10), Inches(0.06))
    fill_shape(accent, TEAL)
    accent.line.fill.background()


def add_footer(slide, text: str = "MOSIP Infrastructure • Self-Service Deployment KT") -> None:
    foot = slide.shapes.add_textbox(Inches(0.45), Inches(7.05), Inches(9), Inches(0.3))
    set_text(foot, text, size=9, color=MUTED, align=PP_ALIGN.LEFT)


def add_bullet_area(slide, items: list[str], top=1.35, height=5.5, size=16) -> None:
    box = slide.shapes.add_textbox(Inches(0.55), Inches(top), Inches(8.9), Inches(height))
    tf = box.text_frame
    tf.word_wrap = True
    tf.clear()
    for i, item in enumerate(items):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.text = item
        p.level = 1 if item.startswith("  ") else 0
        p.font.size = Pt(size if p.level == 0 else size - 2)
        p.font.color.rgb = BODY
        p.space_after = Pt(6)
        if p.level == 0 and not item.startswith(" "):
            p.font.bold = True


def blank_content_slide(prs: Presentation):
    slide = prs.slides.add_slide(prs.slide_layouts[6])  # blank
    bg = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, prs.slide_width, prs.slide_height)
    fill_shape(bg, WHITE)
    bg.line.fill.background()
    # send to back by z-order (first shape is back)
    return slide


def add_content_slide(
    prs: Presentation,
    title: str,
    bullets: list[str],
    speaker: str,
    subtitle: str | None = None,
) -> None:
    slide = blank_content_slide(prs)
    add_header_bar(slide, title, subtitle)
    add_bullet_area(slide, bullets)
    add_footer(slide)
    notes(slide, speaker)


def add_title_slide(prs: Presentation, title: str, subtitle: str, speaker: str) -> None:
    slide = blank_content_slide(prs)
    # gradient-like bands
    top = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, 0, Inches(10), Inches(7.5))
    fill_shape(top, NAVY)
    top.line.fill.background()
    band = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, 0, Inches(4.8), Inches(10), Inches(2.7))
    fill_shape(band, TEAL)
    band.line.fill.background()

    if LOGO.exists():
        slide.shapes.add_picture(str(LOGO), Inches(0.75), Inches(0.65), height=Inches(0.95))

    tbox = slide.shapes.add_textbox(Inches(0.75), Inches(2.0), Inches(8.5), Inches(1.4))
    set_text(tbox, title, size=40, bold=True, color=WHITE, align=PP_ALIGN.LEFT)

    sbox = slide.shapes.add_textbox(Inches(0.75), Inches(3.45), Inches(8.5), Inches(1.2))
    set_text(sbox, subtitle, size=18, color=WHITE, align=PP_ALIGN.LEFT)

    tag = slide.shapes.add_textbox(Inches(0.75), Inches(5.15), Inches(8.5), Inches(0.5))
    set_text(tag, "Dev & QA Teams  •  GitHub Actions  •  August 2026", size=14, color=WHITE, align=PP_ALIGN.LEFT)
    notes(slide, speaker)


def flow_box(
    slide,
    left,
    top,
    width,
    height,
    text: str,
    fill: RGBColor,
    text_color: RGBColor = WHITE,
    font_size: int = 11,
) -> None:
    shape = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, left, top, width, height)
    fill_shape(shape, fill, line=WHITE)
    set_text(shape, text, size=font_size, bold=True, color=text_color)


def arrow_down(slide, cx, y1, y2) -> None:
    conn = slide.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, cx, y1, cx, y2)
    conn.line.color.rgb = TEAL
    conn.line.width = Pt(2.5)


def arrow_right(slide, x1, y, x2) -> None:
    conn = slide.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, x1, y, x2, y)
    conn.line.color.rgb = TEAL
    conn.line.width = Pt(2.5)


def add_diagram_slide(
    prs: Presentation,
    title: str,
    speaker: str,
    draw_fn,
    subtitle: str | None = None,
) -> None:
    slide = blank_content_slide(prs)
    add_header_bar(slide, title, subtitle)
    draw_fn(slide)
    add_footer(slide)
    notes(slide, speaker)


def draw_phase_architecture(slide) -> None:
    phases = [
        ("PHASE 0 — DevOps (once)", "base-infra\nVPC • Jump server • WireGuard", NAVY),
        ("PHASE 1 — QA/Dev (per env)", "Branch → tfvars → WireGuard → Terraform\n→ Helmsman External → MOSIP → Test rigs", TEAL),
        ("PHASE 2 — Teardown", "Helmsman destroy → terraform destroy\n→ WireGuard offboard", ORANGE),
    ]
    y = Inches(1.55)
    cx = Inches(5.0)
    for i, (label, detail, color) in enumerate(phases):
        flow_box(slide, Inches(1.2), y, Inches(7.6), Inches(1.15), f"{label}\n{detail}", color, font_size=13)
        if i < len(phases) - 1:
            arrow_down(slide, cx, y + Inches(1.15), y + Inches(1.45))
        y += Inches(1.45)


def draw_branch_environment(slide) -> None:
    boxes = [
        (Inches(0.6), "Git Branch\nqajava11", TEAL),
        (Inches(3.5), "GitHub Environment\nqajava11", PURPLE),
        (Inches(6.4), "Environment Secrets\nKUBECONFIG, TF_WG_CONFIG…", NAVY),
    ]
    for left, text, color in boxes:
        flow_box(slide, left, Inches(2.8), Inches(2.5), Inches(1.3), text, color, font_size=12)
    arrow_right(slide, Inches(3.1), Inches(3.45), Inches(3.5))
    arrow_right(slide, Inches(6.0), Inches(3.45), Inches(6.4))
    hint = slide.shapes.add_textbox(Inches(1.0), Inches(4.6), Inches(8), Inches(0.8))
    set_text(
        hint,
        "Rule: branch name MUST match environment name — all workflows use github.ref_name",
        size=14,
        color=MUTED,
        align=PP_ALIGN.CENTER,
    )


def draw_ten_step_pipeline(slide) -> None:
    steps = [
        "1 Branch", "2 tfvars", "3 WireGuard", "4 Secrets",
        "5 Terraform", "6 External", "7 MOSIP", "8 Test rigs",
    ]
    x, y = Inches(0.35), Inches(1.6)
    w, h = Inches(1.15), Inches(0.72)
    colors = [TEAL, TEAL, TEAL, PURPLE, NAVY, ORANGE, GREEN, SKY]
    for i, (step, color) in enumerate(zip(steps, colors)):
        col, row = i % 4, i // 4
        left = x + col * Inches(2.35)
        top = y + row * Inches(1.35)
        flow_box(slide, left, top, w, h, step, color, font_size=10)
        if col < 3 and row == 0:
            arrow_right(slide, left + w, top + h // 2, left + w + Inches(0.35))
        if i == 3:
            arrow_down(slide, left + w // 2 + Inches(0.35), top + h, top + Inches(0.55))
    legend = slide.shapes.add_textbox(Inches(0.5), Inches(4.85), Inches(9), Inches(1.8))
    tf = legend.text_frame
    tf.word_wrap = True
    lines = [
        "Steps 1–4: Prepare environment (QA/Dev)",
        "Step 5: Infrastructure + Rancher + KUBECONFIG (automated)",
        "Steps 6–7: Application stack (External auto-triggers MOSIP)",
        "Step 8: Optional test automation",
    ]
    for i, line in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.text = f"▸ {line}"
        p.font.size = Pt(13)
        p.font.color.rgb = BODY


def draw_rancher_flow(slide) -> None:
    steps = [
        "Mint import URL",
        "Plan",
        "Refresh URL",
        "Apply",
        "SSH import",
        "RBAC grants",
        "Publish KUBECONFIG",
        "Commit state",
    ]
    x, y = Inches(0.4), Inches(1.55)
    w, h = Inches(1.08), Inches(0.65)
    for i, step in enumerate(steps):
        col, row = i % 4, i // 4
        left = x + col * Inches(2.35)
        top = y + row * Inches(1.05)
        color = NAVY if step in ("Apply", "Publish KUBECONFIG") else TEAL
        flow_box(slide, left, top, w, h, step, color, font_size=9)
        if col < 3:
            arrow_right(slide, left + w, top + h // 2, left + w + Inches(0.35))
        if i == 3:
            arrow_down(slide, left + w // 2 + Inches(0.35), top + h, top + Inches(0.35))
    badge = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(0.5), Inches(4.5), Inches(9), Inches(0.55))
    fill_shape(badge, LIGHT_BG, line=TEAL)
    set_text(
        badge,
        "Inputs: ENABLE_RANCHER_IMPORT=true  •  PUBLISH_KUBECONFIG=true  •  RANCHER_API_URL + TOKEN",
        size=12,
        bold=True,
        color=NAVY,
    )


def draw_helmsman_cascade(slide) -> None:
    flow_box(slide, Inches(1.0), Inches(2.0), Inches(2.2), Inches(1.0), "Helmsman\nExternal", ORANGE)
    flow_box(slide, Inches(3.9), Inches(2.0), Inches(2.2), Inches(1.0), "Helmsman\nMOSIP", GREEN)
    flow_box(slide, Inches(6.8), Inches(2.0), Inches(2.2), Inches(1.0), "Test Rigs\n(optional)", SKY, text_color=NAVY)
    arrow_right(slide, Inches(3.2), Inches(2.5), Inches(3.9))
    arrow_right(slide, Inches(6.1), Inches(2.5), Inches(6.8))

    details = [
        ("prereq + external DSF", "Istio • Keycloak • Kafka • MinIO"),
        ("mosip-dsf.yaml", "All MOSIP core services"),
        ("testrigs-dsf.yaml", "API / UI automation"),
    ]
    for i, (title, sub) in enumerate(details):
        left = Inches(1.0) + i * Inches(2.9)
        box = slide.shapes.add_textbox(left, Inches(3.35), Inches(2.5), Inches(1.2))
        set_text(box, f"{title}\n{sub}", size=11, color=MUTED)

    warn = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(1.5), Inches(4.85), Inches(7), Inches(0.6))
    fill_shape(warn, RGBColor(0xFF, 0xF3, 0xE0), line=ORANGE)
    set_text(warn, "Always use mode=apply — dry-run fails validation", size=13, bold=True, color=ORANGE)


def draw_teardown_flow(slide) -> None:
    steps = [
        ("Helmsman Destroy\n(optional)", ORANGE),
        ("terraform destroy\nTERRAFORM_DESTROY=true", NAVY),
        ("WireGuard offboard\n(optional)", TEAL),
    ]
    for i, (text, color) in enumerate(steps):
        left = Inches(0.9) + i * Inches(3.05)
        flow_box(slide, left, Inches(2.5), Inches(2.5), Inches(1.2), text, color, font_size=12)
        if i < 2:
            arrow_right(slide, left + Inches(2.5), Inches(3.1), left + Inches(3.05))
    note = slide.shapes.add_textbox(Inches(0.8), Inches(4.2), Inches(8.4), Inches(1.5))
    set_text(
        note,
        "Destroy auto-disables Rancher import — no tfvars edit needed\n"
        "Re-run destroy if git commit step fails (e.g. branch names with parentheses)",
        size=13,
        color=BODY,
        align=PP_ALIGN.CENTER,
    )


def draw_secrets_flow(slide) -> None:
    groups = [
        ("Repository\n(one-time)", "GPG • AWS • SSH • GH_INFRA_PAT", NAVY),
        ("Auto-published\n(per env)", "TF_WG_CONFIG • WG0/WG1 • KUBECONFIG", TEAL),
        ("Manual\n(per env)", "Rancher API • Captcha (6 keys)", PURPLE),
    ]
    for i, (title, items, color) in enumerate(groups):
        left = Inches(0.55) + i * Inches(3.15)
        flow_box(slide, left, Inches(1.7), Inches(2.85), Inches(0.65), title, color, font_size=11)
        box = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, left, Inches(2.5), Inches(2.85), Inches(2.5))
        fill_shape(box, LIGHT_BG, line=color)
        set_text(box, items, size=12, color=BODY)


def add_step_slide(
    prs: Presentation,
    step_num: int,
    title: str,
    bullets: list[str],
    speaker: str,
    accent: RGBColor = TEAL,
) -> None:
    slide = blank_content_slide(prs)
    # step badge
    badge = slide.shapes.add_shape(MSO_SHAPE.OVAL, Inches(0.45), Inches(1.25), Inches(0.75), Inches(0.75))
    fill_shape(badge, accent)
    set_text(badge, str(step_num), size=28, bold=True, color=WHITE)
    add_header_bar(slide, title)
    add_bullet_area(slide, bullets, top=1.35)
    add_footer(slide)
    notes(slide, speaker)


def build() -> None:
    ensure_logo()
    prs = Presentation()
    prs.slide_width = Inches(10)
    prs.slide_height = Inches(7.5)

    add_title_slide(
        prs,
        "MOSIP New Environment\nDeployment",
        "Knowledge Transfer Session\nSelf-Service GitHub Actions Workflow",
        "Welcome the audience. Set expectation: QA/Dev can deploy a full MOSIP env with minimal DevOps "
        "involvement. Duration ~60–90 min. Share docs/SELF_SERVICE_DEPLOYMENT_GUIDE.md after session.",
    )

    add_content_slide(
        prs,
        "Agenda",
        [
            "Core concepts & architecture (with flow diagrams)",
            "Phase 0: one-time DevOps platform setup",
            "Phase 1: 8 deployment steps for each new environment",
            "Terraform + Rancher automation deep-dive",
            "Helmsman application deployment cascade",
            "Secrets checklist & verification sign-off",
            "Common mistakes & teardown",
            "Q&A",
        ],
        "Walk through agenda. Emphasize live demo of GitHub Actions if possible. "
        "Point attendees to the PPT + self-service guide for later reference.",
    )

    add_diagram_slide(
        prs,
        "Who Does What?",
        "DevOps owns Phase 0 once per VPC. QA/Dev own Phase 1 per environment. "
        "Draw the line: routine env creation should not need a DevOps ticket.",
        draw_phase_architecture,
        "Three phases: platform setup → per-env deploy → teardown",
    )

    add_diagram_slide(
        prs,
        "Core Concept: Branch = Environment",
        "This is the #1 concept. Show GitHub Settings → Environments with branch name. "
        "If branch is qajava11, ALL secrets go under environment qajava11 — not repository secrets.",
        draw_branch_environment,
    )

    add_content_slide(
        prs,
        "Deployment Profiles",
        [
            "mosip — Full MOSIP platform (7-node K8s cluster)",
            "  tfvars: profiles/mosip/aws.tfvars",
            "  Helmsman: mosip-platform-1.2.0.x/ or 1.2.1.x/",
            "esignet-standalone — eSignet only (4-node cluster)",
            "  tfvars: profiles/esignet-standalone/aws.tfvars",
            "  Helmsman: esignet-standalone/",
            "Profile picks both Terraform sizing AND Helmsman DSF folder — keep them aligned",
        ],
        "Ask which MOSIP release the team targets — that determines Helmsman profile folder. "
        "Most QA envs use mosip profile.",
    )

    add_diagram_slide(
        prs,
        "10-Step Deployment Pipeline",
        "Overview slide before diving into each step. QA teams can screenshot this as their cheat sheet.",
        draw_ten_step_pipeline,
        "Per-environment flow from branch creation to optional test rigs",
    )

    add_content_slide(
        prs,
        "Automated vs Manual",
        [
            "✅ Automated: WireGuard peers, Rancher import, KUBECONFIG publish, DSF domains",
            "✅ Automated: Post-apply Rancher SSH import (fresh token)",
            "✅ Automated: Runtime tfvars — no rancher_import_url in profile tfvars",
            "📝 Manual: Google reCAPTCHA keys (6 per env)",
            "📝 Manual: Route53 zone_id, AMI in tfvars",
            "📝 Manual: Partner onboarding verification in MinIO",
        ],
        "Set expectations on what QA still must do. Captcha is the biggest manual chunk. "
        "Everything else is workflow-driven on the automation branch.",
    )

    add_content_slide(
        prs,
        "Phase 0 — DevOps One-Time Setup",
        [
            "Repository secrets: GPG_PASSPHRASE, AWS keys, mosip-aws, GH_INFRA_PAT",
            "WireGuard: ACTION_PAT, MOSIP_AWS_PEM (for onboard workflow)",
            "Workflow: terraform plan/apply → base-infra, TERRAFORM_APPLY=true",
            "Edit: terraform/implementations/aws/base-infra/aws.tfvars",
            "Output: Jump server public IP (needed for WireGuard onboard)",
            "Optional: observ-infra + Keycloak-Rancher SAML for Rancher SSO",
        ],
        "DevOps-only section. QA can skip unless setting up a new VPC. "
        "Mention self-hosted runner requirement for WireGuard onboard workflow.",
    )

    add_step_slide(
        prs,
        1,
        "Create Deployment Branch",
        [
            "git clone → checkout automation branch",
            "git checkout -b qajava11",
            "git push -u origin qajava11",
            "Branch name becomes GitHub Environment name",
            "Commit profile tfvars on this branch",
        ],
        "Demo: show branch creation in GitHub. Warn: branch name must be valid and match env name exactly.",
        TEAL,
    )

    add_step_slide(
        prs,
        2,
        "Edit Terraform tfvars",
        [
            "File: profiles/mosip/aws.tfvars",
            "cluster_name + cluster_env_domain must match Helmsman inputs",
            "zone_id, ami, vpc_name, ssh_key_name",
            "enable_postgresql_setup=true, postgresql_port=5433",
            "mosip_infra_branch=develop (use develop, not perfm)",
            "Do NOT set rancher_import_url when using ENABLE_RANCHER_IMPORT",
        ],
        "Walk through tfvars file in repo. Highlight mosip_infra_branch=develop — common mistake is perfm.",
        TEAL,
    )

    add_step_slide(
        prs,
        3,
        "WireGuard Onboard (Automated)",
        [
            "Workflow: WireGuard onboard environment",
            "Requires: self-hosted runner, MOSIP_AWS_PEM, ACTION_PAT",
            "ENV_NAME=qajava11, JUMPSERVER_HOST=<jump IP>",
            "DRY_RUN=true first, then false",
            "Creates: TF_WG_CONFIG, CLUSTER_WIREGUARD_WG0, WG1",
            "Must complete BEFORE terraform infra",
        ],
        "Demo DRY_RUN output if possible. Stress order: WireGuard before Terraform. "
        "Without TF_WG_CONFIG, infra workflow fails immediately.",
        PURPLE,
    )

    add_diagram_slide(
        prs,
        "Secrets & Variables Map",
        "Show GitHub Environments UI. Three buckets: repo secrets, auto-published, manual per env.",
        draw_secrets_flow,
        "Where each secret comes from",
    )

    add_step_slide(
        prs,
        4,
        "Captcha, Rancher API & Env Variables",
        [
            "Create 6 reCAPTCHA v2 keys (prereg, admin, resident domains)",
            "Set captcha secrets on Environment qajava11",
            "Variables: DOMAIN_NAME, ENV_NAME, CLUSTER_ID, DB_PORT=5433",
            "Secrets: RANCHER_API_URL (no /v3), RANCHER_API_TOKEN",
            "Location: Settings → Environments → qajava11",
        ],
        "Captcha takes ~15 min. Rancher token from Rancher UI → Account & API Keys. "
        "CLUSTER_ID can be set after first deploy if unknown.",
        PURPLE,
    )

    add_step_slide(
        prs,
        5,
        "Terraform Infra — Workflow Inputs",
        [
            "Workflow: terraform plan / apply",
            "TERRAFORM_COMPONENT=infra, INFRA_PROFILE=mosip",
            "TERRAFORM_APPLY ✅  ENABLE_RANCHER_IMPORT ✅",
            "PUBLISH_KUBECONFIG ✅ (default)",
            "RANCHER_CLUSTER_NAME optional (defaults to branch)",
            "Prerequisites: TF_WG_CONFIG + RANCHER_API_* must exist",
        ],
        "Demo: Run workflow form in GitHub Actions. Show checkboxes. "
        "GRANT_GROUP_ACCESS enables multi-team RBAC from rancher-access-grants.json.",
        NAVY,
    )

    add_diagram_slide(
        prs,
        "Terraform + Rancher Internal Flow",
        "Key technical slide for Dev audience. Explain why URL is refreshed before apply "
        "(stale token caused production issues). Post-apply SSH import is the reliability fix.",
        draw_rancher_flow,
        "8 automated steps inside terraform plan/apply when Rancher import enabled",
    )

    add_step_slide(
        prs,
        5,
        "After Terraform — Verify",
        [
            "Environment secret KUBECONFIG exists (auto-published)",
            "Rancher UI: cluster state = Active",
            "kubectl get nodes — all Ready",
            "kubectl get pods -n cattle-system — agent Running",
            "Copy CLUSTER_ID for Helmsman (e.g. c-c8ms8)",
            "If publish failed: check Apply Rancher import step logs",
        ],
        "Show successful Actions run. Open Rancher UI. Show KUBECONFIG in GitHub env secrets. "
        "Troubleshoot: cattle-cluster-agent not Running = network or stale import.",
        NAVY,
    )

    add_diagram_slide(
        prs,
        "Helmsman Deployment Cascade",
        "External workflow triggers MOSIP automatically on success. Always apply mode.",
        draw_helmsman_cascade,
        "Application layer after infrastructure is ready",
    )

    add_step_slide(
        prs,
        6,
        "Helmsman External (Prereq + External)",
        [
            "Workflow: Deploy External services of mosip using Helmsman",
            "mode=apply ⚠️ NOT dry-run",
            "profile, domain_name, env_name, db_port=5433, clusterid",
            "Parallel: prereq-dsf + external-dsf",
            "Istio, monitoring, Keycloak, Kafka, MinIO, ActiveMQ",
            "Success → auto-triggers Helmsman MOSIP",
        ],
        "Duration ~70–110 min. Show workflow inputs. clusterid from Rancher is required for monitoring.",
        ORANGE,
    )

    add_step_slide(
        prs,
        7,
        "Helmsman MOSIP (Automatic)",
        [
            "Usually auto-triggered after Step 6",
            "Deploys mosip-dsf.yaml — all core services",
            "Duration ~25–35 minutes",
            "Monitor: kubectl get pods -n mosip",
            "Wait for partner onboarder job Completed",
        ],
        "If auto-trigger fails, run manually with same inputs. "
        "Partner onboarder completion is required before test rigs.",
        GREEN,
    )

    add_step_slide(
        prs,
        8,
        "Helmsman Test Rigs (Optional)",
        [
            "Run ONLY after all MOSIP pods Running",
            "Workflow: Deploy Testrigs of mosip using Helmsman",
            "mode=apply, profile=mosip-platform-1.2.0.x",
            "Deploys testrigs-dsf.yaml",
            "Skip if not doing automated API/UI testing",
        ],
        "Optional step. Common mistake: running test rigs before MOSIP healthy.",
        SKY,
    )

    add_content_slide(
        prs,
        "Verification & Sign-Off",
        [
            "Infra: nodes Ready, KUBECONFIG secret, Rancher Active",
            "External: istio-system, keycloak, kafka, minio pods Running",
            "MOSIP: all mosip namespace pods Running",
            "Portals: admin, prereg, resident, iam.qajava11.mosip.net",
            "Partner onboarder Completed — MinIO reports",
            "Use QA sign-off checklist in SELF_SERVICE_DEPLOYMENT_GUIDE.md",
        ],
        "Walk through URL checks in browser if VPN connected. "
        "Provide sign-off checklist template to team leads.",
    )

    add_content_slide(
        prs,
        "Common Mistakes to Avoid",
        [
            "❌ Branch ≠ Environment name → secrets not found",
            "❌ Skipped WireGuard → TF_WG_CONFIG missing",
            "❌ Missing RANCHER_API_* → import/kubeconfig fails",
            "❌ Helmsman dry-run → validation errors",
            "❌ Wrong CLUSTER_ID → monitoring broken",
            "❌ mosip_infra_branch=perfm → use develop",
            "❌ Test rigs before MOSIP healthy",
        ],
        "Quick fire round. Ask audience which they've hit. "
        "Most common: WireGuard order, dry-run, branch/env mismatch.",
    )

    add_diagram_slide(
        prs,
        "Teardown Flow",
        "When env is done: destroy apps first (optional), then terraform destroy. "
        "Rancher import auto-disabled — no tfvars edit.",
        draw_teardown_flow,
        "Safe environment cleanup",
    )

    add_content_slide(
        prs,
        "Documentation & Next Steps",
        [
            "docs/SELF_SERVICE_DEPLOYMENT_GUIDE.md — full written guide",
            "docs/WORKFLOW_GUIDE.md — GitHub Actions UI walkthrough",
            "docs/SECRET_GENERATION_GUIDE.md — credentials setup",
            "docs/ENVIRONMENT_DESTRUCTION_GUIDE.md — teardown details",
            "docs/DSF_CONFIGURATION_GUIDE.md — Helmsman config",
            "Share this PPT + guide link with all attendees",
        ],
        "Close with resources. Offer office hours for first solo deploy. "
        "Collect feedback on doc gaps.",
    )

    add_title_slide(
        prs,
        "Questions?",
        "Thank you — happy deploying!\nmosip/infra • Self-Service Automation",
        "Open floor. Typical questions: captcha setup time, CLUSTER_ID timing, "
        "what to do when kubeconfig publish times out, destroy re-run scenario.",
    )

    prs.save(OUT)
    print(f"Wrote {OUT} ({len(prs.slides)} slides)")


if __name__ == "__main__":
    build()
