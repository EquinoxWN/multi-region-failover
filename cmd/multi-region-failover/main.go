// Command multi-region-failover checks that the two regional stacks in terraform/ are built the
// same way, and estimates the monthly cost of each from their sizing.
package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/EquinoxWN/multi-region-failover/internal/cost"
	"github.com/EquinoxWN/multi-region-failover/internal/parity"
)

func main() {
	dir := flag.String("dir", "terraform", "Terraform root module")
	flag.Parse()
	os.Exit(run(*dir))
}

func run(dir string) int {
	rep, err := parity.Check(dir)
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		return 2
	}
	fmt.Printf("Parity of module \"primary\" and module \"standby\" (%s): %d settings compared\n", parity.StackSource, len(rep.Attributes))
	if !rep.OK() {
		for _, v := range rep.Violations {
			fmt.Println("  DRIFT:", v)
		}
		return 1
	}
	fmt.Println("  identical apart from the region's role (provider alias, name, VPC range, sizing)")
	fmt.Println()
	totals := map[string]float64{}
	for _, name := range []string{"primary", "standby"} {
		s, err := cost.ReadSizing(dir, name)
		if err != nil {
			fmt.Fprintln(os.Stderr, "error:", err)
			return 2
		}
		lines, err := cost.Monthly(s)
		if err != nil {
			fmt.Fprintln(os.Stderr, "error:", err)
			return 2
		}
		fmt.Printf("Estimated fixed monthly cost, %s (%s):\n", name, cost.PricesAsOf)
		for _, l := range lines {
			fmt.Printf("  %-44s %9.2f USD\n", l.Item, l.Monthly)
		}
		totals[name] = cost.Total(lines)
		fmt.Printf("  %-44s %9.2f USD\n\n", "total", totals[name])
	}
	fmt.Printf("The warm standby costs %.0f%% of the primary before usage-based charges\n", 100*totals["standby"]/totals["primary"])
	fmt.Println("(Aurora storage, I/O and replicated writes, data transfer and traffic are not included).")
	return 0
}
