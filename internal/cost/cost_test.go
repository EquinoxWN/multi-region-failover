package cost

import (
	"math"
	"os"
	"path/filepath"
	"testing"
)

func TestMonthlyCostOfAKnownSizing(t *testing.T) {
	lines, err := Monthly(Sizing{AppDesiredCount: 1, AppCPU: 512, AppMemory: 1024, DBInstanceClass: "db.r6g.large", DBInstanceCount: 1})
	if err != nil {
		t.Fatal(err)
	}
	// Fargate: 0.5 vCPU x 0.04048 + 1 GB x 0.004445 = 0.024685 per hour.
	want := []float64{0.024685 * 730, 0.26 * 730, 0.045 * 730, (0.0225 + 0.008) * 730, 1}
	for i, l := range lines {
		if math.Abs(l.Monthly-want[i]) > 1e-9 {
			t.Errorf("%s: %.4f, want %.4f", l.Item, l.Monthly, want[i])
		}
	}
	if total := Total(lines); math.Abs(total-(18.02005+189.8+32.85+22.265+1)) > 1e-6 {
		t.Fatalf("total %.5f", total)
	}
	if _, err := Monthly(Sizing{DBInstanceClass: "db.x99.huge"}); err == nil {
		t.Fatal("an unknown instance class must be an error")
	}
}

func TestSizingIsReadFromTheVariableDefaults(t *testing.T) {
	s, err := ReadSizing("../../terraform", "standby")
	if err != nil {
		t.Fatal(err)
	}
	if s != (Sizing{AppDesiredCount: 1, AppCPU: 512, AppMemory: 1024, DBInstanceClass: "db.r6g.large", DBInstanceCount: 1}) {
		t.Fatalf("standby sizing %+v", s)
	}
	p, err := ReadSizing("../../terraform", "primary")
	if err != nil || p.AppDesiredCount != 3 || p.DBInstanceCount != 2 {
		t.Fatalf("primary sizing %+v %v", p, err)
	}
	if _, err := ReadSizing("../../terraform", "nope"); err == nil {
		t.Fatal("a missing variable must be an error")
	}
}

func TestMalformedSizingIsAnError(t *testing.T) {
	dir := t.TempDir()
	src := `variable "standby" {
  default = { app_desired_count = "one", app_cpu = 512, app_memory = 1024, db_instance_class = "db.r6g.large", db_instance_count = 1 }
}`
	if err := os.WriteFile(filepath.Join(dir, "variables.tf"), []byte(src), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := ReadSizing(dir, "standby"); err == nil {
		t.Fatal("a text count must be an error")
	}
}
