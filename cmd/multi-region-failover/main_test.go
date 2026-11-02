package main

import "testing"

func TestTheCommandExitsZeroOnTheRepositoryAndTwoOnBadInput(t *testing.T) {
	if code := run("../../terraform"); code != 0 {
		t.Fatalf("run(terraform) = %d, want 0", code)
	}
	if code := run(t.TempDir()); code != 2 {
		t.Fatalf("run(empty dir) = %d, want 2", code)
	}
}
