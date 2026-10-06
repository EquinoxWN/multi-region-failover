package parity

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestTheRepositorysStacksMatch(t *testing.T) {
	rep, err := Check("../../terraform")
	if err != nil {
		t.Fatal(err)
	}
	if !rep.OK() {
		t.Fatalf("violations: %v", rep.Violations)
	}
	if len(rep.Attributes) < 14 {
		t.Fatalf("compared only %v", rep.Attributes)
	}
}

const good = `
module "primary" {
  source    = "./modules/regional_stack"
  providers = { aws = aws.primary }
  role      = "primary"
  name      = "${var.name}-primary"
  app_image = var.app_image
  vpc_cidr  = var.primary.vpc_cidr
}

module "standby" {
  source     = "./modules/regional_stack"
  providers  = { aws = aws.standby }
  role       = "standby"
  name       = "${var.name}-standby"
  app_image  = var.app_image
  vpc_cidr   = var.standby.vpc_cidr
  depends_on = [module.primary]
}
`

func check(t *testing.T, src string) Report {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "main.tf"), []byte(src), 0o600); err != nil {
		t.Fatal(err)
	}
	rep, err := Check(dir)
	if err != nil {
		t.Fatal(err)
	}
	return rep
}

func TestStacksThatDifferOnlyByRoleAreEquivalent(t *testing.T) {
	if rep := check(t, good); !rep.OK() {
		t.Fatalf("violations: %v", rep.Violations)
	}
}

func TestDriftIsReported(t *testing.T) {
	cases := map[string]struct{ from, to, want string }{
		"a different image":        {"app_image  = var.app_image\n  vpc", "app_image  = \"repo/api:latest\"\n  vpc", "app_image differs"},
		"a setting on one side":    {"  depends_on = [module.primary]", "  depends_on = [module.primary]\n  az_count = 3", "az_count is set only on the standby"},
		"swapped roles":            {`role       = "standby"`, `role       = "primary"`, "role must be"},
		"a hard-coded value":       {"vpc_cidr   = var.standby.vpc_cidr", `vpc_cidr   = "10.99.0.0/16"`, "vpc_cidr differs"},
		"a different module":       {"source     = \"./modules/regional_stack\"\n  providers  = { aws = aws.standby }", "source     = \"./modules/other\"\n  providers  = { aws = aws.standby }", "expected exactly two stacks"},
		"the wrong provider alias": {"providers  = { aws = aws.standby }", "providers  = { aws = aws.primary }", "providers of the standby refers to the primary"},
	}
	for name, c := range cases {
		if !strings.Contains(good, c.from) {
			t.Fatalf("%s: fixture does not contain %q", name, c.from)
		}
		rep := check(t, strings.Replace(good, c.from, c.to, 1))
		if rep.OK() || !strings.Contains(strings.Join(rep.Violations, "\n"), c.want) {
			t.Errorf("%s: violations %v, want one containing %q", name, rep.Violations, c.want)
		}
	}
}

func TestBadInputIsAnError(t *testing.T) {
	if _, err := Check(t.TempDir()); err == nil {
		t.Fatal("a directory without .tf files must be an error")
	}
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "main.tf"), []byte("module \"x\" {"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := Check(dir); err == nil {
		t.Fatal("unparsable HCL must be an error")
	}
}
