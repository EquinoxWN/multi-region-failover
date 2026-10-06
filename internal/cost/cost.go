// Package cost estimates the monthly price of each stack from its sizing variables, so the
// standby's cost is known before anything is deployed.
package cost

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/hashicorp/hcl/v2"
	"github.com/hashicorp/hcl/v2/hclsyntax"
	"github.com/zclconf/go-cty/cty"
)

// HoursPerMonth is AWS's convention for monthly prices.
const HoursPerMonth = 730

// Prices are on-demand list prices in USD for us-east-1 and us-west-2, which AWS prices the same
// for these items. They were copied from the AWS pricing pages when this table was written
// (see PricesAsOf) and change over time: check the AWS Pricing Calculator before relying on them.
var Prices = struct {
	FargateVCPUHour, FargateGBHour      float64
	AuroraInstanceHour                  map[string]float64
	NATGatewayHour, ALBHour, ALBLCUHour float64
	KMSKeyMonth                         float64
}{
	FargateVCPUHour:    0.04048,
	FargateGBHour:      0.004445,
	AuroraInstanceHour: map[string]float64{"db.r6g.large": 0.26, "db.r6g.xlarge": 0.519, "db.r7g.large": 0.276},
	NATGatewayHour:     0.045,
	ALBHour:            0.0225,
	ALBLCUHour:         0.008,
	KMSKeyMonth:        1.0,
}

// PricesAsOf says when the table above was taken.
const PricesAsOf = "2025 list prices"

// Sizing is one stack's sizing variable.
type Sizing struct {
	AppDesiredCount int
	AppCPU          int // Fargate CPU units (1024 = 1 vCPU)
	AppMemory       int // MiB
	DBInstanceClass string
	DBInstanceCount int
}

// Line is one cost item.
type Line struct {
	Item    string
	Monthly float64
}

// Monthly returns the fixed monthly cost lines of one stack. Usage-based charges (Aurora storage,
// I/O and replicated writes, data transfer, NAT and LCU traffic beyond one LCU) are not included.
func Monthly(s Sizing) ([]Line, error) {
	price, ok := Prices.AuroraInstanceHour[s.DBInstanceClass]
	if !ok {
		return nil, fmt.Errorf("no price for instance class %q", s.DBInstanceClass)
	}
	vcpu := float64(s.AppCPU) / 1024
	gb := float64(s.AppMemory) / 1024
	return []Line{
		{fmt.Sprintf("Fargate: %d task(s) x %.2g vCPU, %.2g GB", s.AppDesiredCount, vcpu, gb),
			float64(s.AppDesiredCount) * (vcpu*Prices.FargateVCPUHour + gb*Prices.FargateGBHour) * HoursPerMonth},
		{fmt.Sprintf("Aurora: %d x %s", s.DBInstanceCount, s.DBInstanceClass), float64(s.DBInstanceCount) * price * HoursPerMonth},
		{"NAT gateway (1, hourly charge)", Prices.NATGatewayHour * HoursPerMonth},
		{"Load balancer (hourly + 1 LCU)", (Prices.ALBHour + Prices.ALBLCUHour) * HoursPerMonth},
		{"KMS key", Prices.KMSKeyMonth},
	}, nil
}

// Total sums lines.
func Total(lines []Line) float64 {
	t := 0.0
	for _, l := range lines {
		t += l.Monthly
	}
	return t
}

// ReadSizing reads the default value of a sizing variable ("primary" or "standby") from
// variables.tf in dir.
func ReadSizing(dir, name string) (Sizing, error) {
	path := filepath.Join(dir, "variables.tf")
	src, err := os.ReadFile(path)
	if err != nil {
		return Sizing{}, err
	}
	file, diags := hclsyntax.ParseConfig(src, path, hcl.InitialPos)
	if diags.HasErrors() {
		return Sizing{}, errors.New(diags.Error())
	}
	body, ok := file.Body.(*hclsyntax.Body)
	if !ok {
		return Sizing{}, errors.New("unexpected body type")
	}
	for _, b := range body.Blocks {
		if b.Type != "variable" || len(b.Labels) != 1 || b.Labels[0] != name {
			continue
		}
		def, ok := b.Body.Attributes["default"]
		if !ok {
			return Sizing{}, fmt.Errorf("variable %q has no default", name)
		}
		v, diags := def.Expr.Value(nil)
		if diags.HasErrors() {
			return Sizing{}, fmt.Errorf("variable %q: %s", name, diags.Error())
		}
		return fromValue(v)
	}
	return Sizing{}, fmt.Errorf("variable %q not found in %s", name, path)
}

func fromValue(v cty.Value) (Sizing, error) {
	if !v.Type().IsObjectType() {
		return Sizing{}, errors.New("sizing default must be an object")
	}
	num := func(k string) (int, error) {
		if !v.Type().HasAttribute(k) {
			return 0, fmt.Errorf("sizing has no %s", k)
		}
		a := v.GetAttr(k)
		if a.Type() != cty.Number {
			return 0, fmt.Errorf("%s must be a number", k)
		}
		f, _ := a.AsBigFloat().Int64()
		return int(f), nil
	}
	var s Sizing
	var err error
	if s.AppDesiredCount, err = num("app_desired_count"); err != nil {
		return s, err
	}
	if s.AppCPU, err = num("app_cpu"); err != nil {
		return s, err
	}
	if s.AppMemory, err = num("app_memory"); err != nil {
		return s, err
	}
	if s.DBInstanceCount, err = num("db_instance_count"); err != nil {
		return s, err
	}
	if !v.Type().HasAttribute("db_instance_class") || v.GetAttr("db_instance_class").Type() != cty.String {
		return s, errors.New("db_instance_class must be a string")
	}
	s.DBInstanceClass = v.GetAttr("db_instance_class").AsString()
	return s, nil
}
