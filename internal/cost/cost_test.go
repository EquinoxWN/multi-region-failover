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
	for _, bad := range []string{"0.5", "-1", "1e9"} {
		src := `variable "standby" {
  default = { app_desired_count = ` + bad + `, app_cpu = 512, app_memory = 1024, db_instance_class = "db.r6g.large", db_instance_count = 1 }
}`
		if err := os.WriteFile(filepath.Join(dir, "variables.tf"), []byte(src), 0o600); err != nil {
			t.Fatal(err)
		}
		if _, err := ReadSizing(dir, "standby"); err == nil {
			t.Errorf("app_desired_count = %s must be an error, not truncated", bad)
		}
	}
}

func TestFargateCostScalesWithTheTaskCount(t *testing.T) {
	one, err := Monthly(Sizing{AppDesiredCount: 1, AppCPU: 512, AppMemory: 1024, DBInstanceClass: "db.r6g.large", DBInstanceCount: 1})
	if err != nil {
		t.Fatal(err)
	}
	three, err := Monthly(Sizing{AppDesiredCount: 3, AppCPU: 512, AppMemory: 1024, DBInstanceClass: "db.r6g.large", DBInstanceCount: 2})
	if err != nil {
		t.Fatal(err)
	}
	if math.Abs(three[0].Monthly-3*one[0].Monthly) > 1e-9 || math.Abs(three[1].Monthly-2*one[1].Monthly) > 1e-9 {
		t.Fatalf("Fargate %.2f vs %.2f, Aurora %.2f vs %.2f", three[0].Monthly, one[0].Monthly, three[1].Monthly, one[1].Monthly)
	}
}
