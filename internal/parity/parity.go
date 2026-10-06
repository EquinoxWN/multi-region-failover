// Package parity reads the Terraform root module and checks that the primary and the standby
// are built from the same module with the same settings, apart from the region's role.
// Drift between the two stacks is how a failover breaks months after it was last tested.
package parity

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"sort"
	"strings"

	"github.com/hashicorp/hcl/v2"
	"github.com/hashicorp/hcl/v2/hclsyntax"
)

// StackSource is the module both regions must use.
const StackSource = "./modules/regional_stack"

// Report is the outcome of a check.
type Report struct {
	Attributes []string // attributes compared
	Violations []string
}

// OK reports whether the two stacks are equivalent.
func (r Report) OK() bool { return len(r.Violations) == 0 }

var role = regexp.MustCompile(`\b(primary|standby)\b`)

// normalise replaces the role word so that `var.primary.vpc_cidr` and `var.standby.vpc_cidr`
// compare equal: they differ only in which region they configure.
func normalise(expr string) string {
	return strings.Join(strings.Fields(role.ReplaceAllString(expr, "ROLE")), " ")
}

type module struct {
	name  string
	attrs map[string]string // attribute name -> source text of its expression
	src   string
}

// Check parses every .tf file in dir.
func Check(dir string) (Report, error) {
	files, err := filepath.Glob(filepath.Join(dir, "*.tf"))
	if err != nil {
		return Report{}, err
	}
	if len(files) == 0 {
		return Report{}, fmt.Errorf("no .tf files in %s", dir)
	}
	sort.Strings(files)
	var stacks []module
	for _, f := range files {
		src, err := os.ReadFile(f)
		if err != nil {
			return Report{}, err
		}
		file, diags := hclsyntax.ParseConfig(src, f, hcl.InitialPos)
		if diags.HasErrors() {
			return Report{}, errors.New(diags.Error())
		}
		body, ok := file.Body.(*hclsyntax.Body)
		if !ok {
			return Report{}, fmt.Errorf("%s: unexpected body type", f)
		}
		for _, b := range body.Blocks {
			if b.Type != "module" || len(b.Labels) != 1 {
				continue
			}
			m := module{name: b.Labels[0], attrs: map[string]string{}}
			for name, a := range b.Body.Attributes {
				r := a.Expr.Range()
				m.attrs[name] = string(src[r.Start.Byte:r.End.Byte])
			}
			for _, inner := range b.Body.Blocks {
				m.attrs["block:"+inner.Type] = "present"
			}
			m.src = strings.Trim(m.attrs["source"], `"`)
			if m.src == StackSource {
				stacks = append(stacks, m)
			}
		}
	}
	return compare(stacks), nil
}

func compare(stacks []module) Report {
	var rep Report
	byName := map[string]module{}
	for _, m := range stacks {
		byName[m.name] = m
	}
	p, okP := byName["primary"]
	s, okS := byName["standby"]
	if len(stacks) != 2 || !okP || !okS {
		names := make([]string, 0, len(stacks))
		for _, m := range stacks {
			names = append(names, m.name)
		}
		rep.Violations = append(rep.Violations, fmt.Sprintf("expected exactly two stacks named primary and standby using %s, found %v", StackSource, names))
		return rep
	}
	keys := map[string]bool{}
	for k := range p.attrs {
		keys[k] = true
	}
	for k := range s.attrs {
		keys[k] = true
	}
	names := make([]string, 0, len(keys))
	for k := range keys {
		names = append(names, k)
	}
	slices.Sort(names)
	for _, k := range names {
		if k == "depends_on" {
			continue // ordering only: the standby must wait for the primary to join the global database
		}
		rep.Attributes = append(rep.Attributes, k)
		pv, inP := p.attrs[k]
		sv, inS := s.attrs[k]
		switch {
		case !inP:
			rep.Violations = append(rep.Violations, fmt.Sprintf("%s is set only on the standby", k))
		case !inS:
			rep.Violations = append(rep.Violations, fmt.Sprintf("%s is set only on the primary", k))
		case k == "role":
			if pv != `"primary"` || sv != `"standby"` {
				rep.Violations = append(rep.Violations, fmt.Sprintf("role must be \"primary\" and \"standby\", got %s and %s", pv, sv))
			}
		case normalise(pv) != normalise(sv):
			rep.Violations = append(rep.Violations, fmt.Sprintf("%s differs beyond the region's role: primary %s, standby %s", k, pv, sv))
		default:
			// Equal after normalising, but each stack may only refer to its own role: a standby
			// wired to aws.primary would build the "standby" in the primary region.
			for _, side := range []struct{ name, expr string }{{"primary", pv}, {"standby", sv}} {
				for _, w := range role.FindAllString(side.expr, -1) {
					if w != side.name {
						rep.Violations = append(rep.Violations, fmt.Sprintf("%s of the %s refers to the %s: %s", k, side.name, w, side.expr))
						break
					}
				}
			}
		}
	}
	return rep
}
