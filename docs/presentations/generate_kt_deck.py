#!/usr/bin/env python3
"""Generate MOSIP self-service deployment KT PowerPoint."""

from pathlib import Path

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.util import Inches, Pt

OUT = Path(__file__).resolve().parent / "MOSIP_New_Environment_Deployment_KT.pptx"

TITLE_COLOR = RGBColor(0x00, 0x33, 0x66)
ACCENT = RGBColor(0x00, 0x66, 0x99)
BODY = RGBColor(0x33, 0x33, 0x33)
WHITE = RGBColor(0xFF, 0xFF, 0xFF)


def set_title(slide, text, subtitle=None):
    slide.shapes.title.text = text
    slide.shapes.title.text_frame.paragraphs[0].font.size = Pt(32)
    slide.shapes.title.text_frame.paragraphs[0].font.bold = True
    slide.shapes.title.text_frame.paragraphs[0].font.color.rgb = TITLE_COLOR
    if subtitle and len(slide.placeholders) > 1:
        sub = slide.placeholders[1]
        sub.text = subtitle
        sub.text_frame.paragraphs[0].font.size = Pt(16)
        sub.text_frame.paragraphs[0].font.color.rgb = ACCENT


def add_bullets(slide, items, level0_size=18):
    body = slide.shapes.placeholders[1].text_frame
    body.clear()
    for i, item in enumerate(items):
        p = body.paragraphs[0] if i == 0 else body.add_paragraph()
        p.text = item
        p.level = 0
        p.font.size = Pt(level0_size)
        p.font.color.rgb = BODY
        p.space_after = Pt(8)


def add_section(prs, title, bullets):
    slide = prs.slides.add_slide(prs.slide_layouts[1])
    set_title(slide, title)
    add_bullets(slide, bullets)


def add_title_slide(prs, title, subtitle):
    slide = prs.slides.add_slide(prs.slide_layouts[0])
    set_title(slide, title, subtitle)


def add_two_column_notes(prs, title, left_title, left_items, right_title, right_items):
    slide = prs.slides.add_slide(prs.slide_layouts[5])  # title only
    set_title(slide, title)
    # text boxes
    left = slide.shapes.add_textbox(Inches(0.5), Inches(1.6), Inches(4.5), Inches(5))
    tf = left.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]
    p.text = left_title
    p.font.bold = True
    p.font.size = Pt(16)
    p.font.color.rgb = ACCENT
    for item in left_items:
        p = tf.add_paragraph()
        p.text = f"• {item}"
        p.font.size = Pt(14)
        p.font.color.rgb = BODY
        p.space_after = Pt(4)

    right = slide.shapes.add_textbox(Inches(5.2), Inches(1.6), Inches(4.5), Inches(5))
    tf = right.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]
    p.text = right_title
    p.font.bold = True
    p.font.size = Pt(16)
    p.font.color.rgb = ACCENT
    for item in right_items:
        p = tf.add_paragraph()
        p.text = f"• {item}"
        p.font.size = Pt(14)
        p.font.color.rgb = BODY
        p.space_after = Pt(4)


def build():
    prs = Presentation()
    prs.slide_width = Inches(10)
    prs.slide_height = Inches(7.5)

    add_title_slide(
        prs,
        "MOSIP New Environment Deployment",
        "Knowledge Transfer for Dev & QA Teams\nSelf-Service GitHub Actions Workflow • August 2026",
    )

    add_section(
        prs,
        "Agenda",
        [
            "Core concepts: branch = environment, deployment profiles",
            "Architecture: Phase 0 (DevOps) vs Phase 1 (QA/Dev per env)",
            "Complete 10-step deployment walkthrough",
            "Terraform + Rancher automation (import & KUBECONFIG)",
            "Helmsman application deployment",
            "Secrets, verification, and sign-off checklist",
            "Common mistakes & teardown overview",
            "Documentation & Q&A",
        ],
    )

    add_section(
        prs,
        "Who Does What?",
        [
            "DevOps (once per platform): base-infra, optional observ-infra/Rancher, repo secrets",
            "QA / Dev (per environment): branch, tfvars, WireGuard onboard, captcha, workflows",
            "Goal: deploy a new env like qajava11 without DevOps for routine steps",
            "Automation branch required (e.g. Ivanmeneges-patch-kubeconfig or develop after merge)",
            "Reference doc: docs/SELF_SERVICE_DEPLOYMENT_GUIDE.md",
        ],
    )

    add_section(
        prs,
        "Core Concept: Branch = Environment",
        [
            "Git branch name = GitHub Environment name = secret scope",
            "Example: branch qajava11 → Settings → Environments → qajava11",
            "All workflows use: environment: ${{ github.ref_name }}",
            "Branch names with parentheses supported (e.g. perfm(issue1919))",
            "Create new env: git checkout -b <env-name> and push",
        ],
    )

    add_section(
        prs,
        "Deployment Profiles",
        [
            "mosip — full MOSIP platform (7-node cluster)",
            "  • tfvars: profiles/mosip/aws.tfvars",
            "  • Helmsman: Helmsman/dsf/mosip-platform-1.2.0.x/ or 1.2.1.x/",
            "esignet-standalone — eSignet only (4-node cluster)",
            "  • tfvars: profiles/esignet-standalone/aws.tfvars",
            "  • Helmsman: Helmsman/dsf/esignet-standalone/",
            "Pick MOSIP version folder to match your release",
        ],
    )

    add_section(
        prs,
        "Architecture Overview",
        [
            "PHASE 0 (one-time, DevOps):",
            "  • terraform plan/apply → base-infra (VPC, jump server, WireGuard server)",
            "  • Optional: observ-infra (Rancher UI + Keycloak) + SAML integration",
            "PHASE 1 (per environment, QA/Dev):",
            "  1. Branch  2. tfvars  3. WireGuard onboard  4. Secrets/vars",
            "  5. Terraform infra  6. Helmsman External  7. Helmsman MOSIP  8. Test rigs",
            "PHASE 2 (teardown): Helmsman destroy → terraform destroy → WireGuard offboard",
        ],
    )

    add_two_column_notes(
        prs,
        "What Is Automated vs Manual?",
        "Automated (self-service)",
        [
            "WireGuard peer allocation → TF_WG_CONFIG, WG0, WG1",
            "Rancher cluster registration (ENABLE_RANCHER_IMPORT=true)",
            "Post-apply Rancher import on control plane (fresh token)",
            "KUBECONFIG publish to env secret (PUBLISH_KUBECONFIG=true)",
            "DSF domain placeholders ${domain_name}",
            "Captcha keys from environment secrets",
        ],
        "Still manual",
        [
            "Google reCAPTCHA key creation (6 keys per env)",
            "Route53 zone ID, AMI ID in tfvars",
            "MOSIP / k8s-infra branch selection in tfvars",
            "Helmsman profile version choice",
            "Partner onboarding verification in MinIO",
        ],
    )

    add_section(
        prs,
        "Phase 0 — DevOps One-Time Setup",
        [
            "Repository secrets: GPG_PASSPHRASE, AWS keys, mosip-aws (SSH), GH_INFRA_PAT",
            "WireGuard onboard secrets: ACTION_PAT, MOSIP_AWS_PEM",
            "Workflow: terraform plan / apply → TERRAFORM_COMPONENT=base-infra, APPLY=true",
            "Edit: terraform/implementations/aws/base-infra/aws.tfvars",
            "Save jump server public IP for WireGuard onboard",
            "Optional: observ-infra + Keycloak-Rancher SAML for Rancher SSO",
        ],
    )

    add_section(
        prs,
        "Step 1 — Create Deployment Branch",
        [
            "git clone https://github.com/YOUR_ORG/infra.git",
            "git checkout <automation-branch>",
            "git checkout -b qajava11    # branch name = environment name",
            "git push -u origin qajava11",
            "GitHub auto-creates Environment when secrets are first written",
        ],
    )

    add_section(
        prs,
        "Step 2 — Edit Terraform tfvars",
        [
            "File: terraform/implementations/aws/infra/profiles/mosip/aws.tfvars",
            "Key fields to set:",
            "  • cluster_name → qajava11",
            "  • cluster_env_domain → qajava11.mosip.net",
            "  • zone_id, ami, vpc_name, ssh_key_name",
            "  • enable_postgresql_setup=true, postgresql_port=5433",
            "  • mosip_infra_branch=develop (NOT perfm — use develop)",
            "Do NOT set rancher_import_url when using ENABLE_RANCHER_IMPORT=true",
            "Commit and push tfvars to your env branch",
        ],
    )

    add_section(
        prs,
        "Step 3 — WireGuard Onboard (Automated)",
        [
            "Workflow: WireGuard onboard environment",
            "Requires: self-hosted runner + MOSIP_AWS_PEM + ACTION_PAT",
            "Inputs: ENV_NAME=qajava11, JUMPSERVER_HOST=<jump IP>",
            "DRY_RUN=true first, then DRY_RUN=false",
            "Creates environment secrets:",
            "  • TF_WG_CONFIG (Terraform VPN)",
            "  • CLUSTER_WIREGUARD_WG0 / WG1 (Helmsman VPN)",
            "Run this BEFORE terraform infra — TF_WG_CONFIG is required",
        ],
    )

    add_section(
        prs,
        "Step 4 — Secrets & Environment Variables",
        [
            "4a. Create 6 reCAPTCHA v2 keys (Google Admin) for prereg/admin/resident domains",
            "4b. Set captcha secrets on Environment qajava11 (PREREG_*, ADMIN_*, RESIDENT_*)",
            "4c. Environment variables: DOMAIN_NAME, ENV_NAME, CLUSTER_ID, DB_PORT=5433",
            "4d. Rancher secrets: RANCHER_API_URL (no /v3), RANCHER_API_TOKEN",
            "Location: Repo → Settings → Environments → qajava11",
        ],
    )

    add_section(
        prs,
        "Step 5 — Terraform Infra Workflow Inputs",
        [
            "Workflow: terraform plan / apply",
            "CLOUD_PROVIDER=aws | TERRAFORM_COMPONENT=infra | INFRA_PROFILE=mosip",
            "TERRAFORM_APPLY=true ✅",
            "ENABLE_RANCHER_IMPORT=true ✅",
            "RANCHER_CLUSTER_NAME=<name> (optional — defaults to branch)",
            "PUBLISH_KUBECONFIG=true ✅ (default)",
            "GRANT_GROUP_ACCESS=false (enable for multi-team RBAC from JSON)",
            "Prerequisites: TF_WG_CONFIG + RANCHER_API_* secrets must exist",
        ],
    )

    add_section(
        prs,
        "Step 5 — What Happens Inside Terraform (Rancher)",
        [
            "1. Generate Rancher import URL via API (plan time)",
            "2. Terraform Plan (with runtime tfvars — fresh import command)",
            "3. Refresh import URL immediately before apply",
            "4. Terraform Apply — EC2, RKE2, DNS, PostgreSQL, Ansible",
            "5. Apply Rancher import on cluster — SSH to control plane, fresh manifest",
            "6. Grant Rancher cluster access (optional — DEVOPS always cluster-owner)",
            "7. Publish KUBECONFIG — wait ~6 min for state=active, set env secret",
            "8. Encrypt state and push to branch",
        ],
    )

    add_section(
        prs,
        "Step 5 — After Terraform: Verify",
        [
            "GitHub Environment has KUBECONFIG secret (auto-published)",
            "Rancher UI → Cluster Management → cluster Active",
            "kubectl get nodes — all Ready (via WireGuard connected)",
            "kubectl get pods -n cattle-system — cattle-cluster-agent Running",
            "Copy CLUSTER_ID (e.g. c-c8ms8) for Helmsman Step 6",
            "If kubeconfig publish failed: check import step + cattle-system pods",
        ],
    )

    add_section(
        prs,
        "Step 6 — Helmsman External (Prereq + External)",
        [
            "Workflow: Deploy External services of mosip using Helmsman",
            "mode=apply ⚠️ NOT dry-run",
            "profile=mosip-platform-1.2.0.x (match your MOSIP version)",
            "domain_name=qajava11.mosip.net | env_name=qajava11 | db_port=5433",
            "clusterid=c-xxxxx (from Rancher UI)",
            "Deploys in parallel: prereq-dsf.yaml + external-dsf.yaml",
            "  • Istio, monitoring, Keycloak, Kafka, MinIO, ActiveMQ, captcha",
            "On success → auto-triggers Helmsman MOSIP workflow",
        ],
    )

    add_section(
        prs,
        "Step 7 — Helmsman MOSIP (Automatic)",
        [
            "Workflow: Deploy Mosip services of mosip using Helmsman",
            "Usually auto-triggered after Step 6 succeeds",
            "If not started: run manually with mode=apply",
            "Deploys: mosip-dsf.yaml — all MOSIP core services",
            "Duration: ~25–35 minutes",
            "Wait for all pods in namespace mosip to be Running",
        ],
    )

    add_section(
        prs,
        "Step 8 — Helmsman Test Rigs (Optional)",
        [
            "Workflow: Deploy Testrigs of mosip using Helmsman",
            "Run ONLY after all MOSIP pods are Running",
            "mode=apply | profile=mosip-platform-1.2.0.x",
            "Deploys: testrigs-dsf.yaml — API/UI/DSL automation",
            "Optional — skip if not doing automated testing",
        ],
    )

    add_section(
        prs,
        "10-Step Quick Reference",
        [
            "1. git checkout -b <env-name>",
            "2. Edit profiles/mosip/aws.tfvars → push",
            "3. WireGuard onboard (DRY_RUN=false)",
            "4. Set captcha secrets (6) + env vars + Rancher API secrets",
            "5. terraform plan/apply → infra, ENABLE_RANCHER_IMPORT=true",
            "6. Deploy External services Helmsman → apply",
            "7. Wait: Deploy Mosip services Helmsman (auto)",
            "8. Deploy Testrigs Helmsman → apply (optional)",
            "9. Verify portals + partner onboarder",
            "10. Sign-off checklist (see guide)",
        ],
    )

    add_section(
        prs,
        "Secrets Checklist (Per Environment)",
        [
            "Auto from WireGuard: TF_WG_CONFIG, CLUSTER_WIREGUARD_WG0, WG1",
            "Auto from Terraform: KUBECONFIG",
            "Manual: RANCHER_API_URL, RANCHER_API_TOKEN",
            "Manual: 6 captcha key pairs (PREREG, ADMIN, RESIDENT × site+secret)",
            "Variables: DOMAIN_NAME, ENV_NAME, CLUSTER_ID, DB_PORT=5433",
            "Optional: SLACK_WEBHOOK_URL, SLACK_CHANNEL_NAME",
        ],
    )

    add_section(
        prs,
        "Verification & Sign-Off URLs",
        [
            "After infra: nodes Ready, KUBECONFIG secret exists, Rancher Active",
            "After External: pods Running in istio-system, keycloak, kafka, minio",
            "After MOSIP: all mosip namespace pods Running",
            "Partner onboarder job Completed — check MinIO reports",
            "Portal URLs (replace qajava11):",
            "  • https://admin.qajava11.mosip.net",
            "  • https://prereg.qajava11.mosip.net",
            "  • https://resident.qajava11.mosip.net",
            "  • https://iam.qajava11.mosip.net/auth",
        ],
    )

    add_section(
        prs,
        "Common Mistakes to Avoid",
        [
            "Branch name ≠ GitHub Environment name → secrets not found",
            "Skipped WireGuard onboard → TF_WG_CONFIG missing",
            "Missing RANCHER_API_* → import/kubeconfig fails",
            "Helmsman dry-run instead of apply → validation errors",
            "Wrong CLUSTER_ID → Grafana/monitoring broken",
            "postgresql.enabled mismatch in DSF vs tfvars",
            "Test rigs before MOSIP pods healthy → immediate failures",
            "mosip_infra_branch=perfm in tfvars — use develop",
        ],
    )

    add_section(
        prs,
        "Teardown Overview (When Done)",
        [
            "1. Optional: Helmsman destroy workflows (MOSIP → external → prereq)",
            "2. terraform destroy — TERRAFORM_DESTROY=true required",
            "   • Rancher import auto-disabled during destroy",
            "   • Removes EC2, cluster, state files from branch",
            "3. Optional: WireGuard offboard — free VPN peers",
            "See: docs/ENVIRONMENT_DESTRUCTION_GUIDE.md",
        ],
    )

    add_section(
        prs,
        "Documentation & Support",
        [
            "docs/SELF_SERVICE_DEPLOYMENT_GUIDE.md — complete step-by-step guide",
            "docs/WORKFLOW_GUIDE.md — GitHub Actions UI walkthrough",
            "docs/SECRET_GENERATION_GUIDE.md — SSH, AWS, Rancher API tokens",
            "docs/DSF_CONFIGURATION_GUIDE.md — Helmsman DSF configuration",
            "docs/ENVIRONMENT_DESTRUCTION_GUIDE.md — safe teardown",
            "docs/ONBOARDING_GUIDE.md — partner onboarding troubleshooting",
            ".github/workflows/README.md — workflow parameter reference",
        ],
    )

    add_title_slide(prs, "Questions?", "Thank you — happy deploying!\nmosip/infra • Self-Service Automation")

    prs.save(OUT)
    print(f"Wrote {OUT} ({len(prs.slides)} slides)")


if __name__ == "__main__":
    build()
