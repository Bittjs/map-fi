package main

import (
	"testing"
	"time"
)

func TestAggregateCounts(t *testing.T) {
	// verify — проверка, остальные типы — жалобы
	checks, complaints := aggregateCounts(map[string]int{
		"verify":         3,
		"wrong_password": 1,
		"point_not_found": 2,
		"spam_fake":       1,
		"other":           0,
	})
	if checks != 3 {
		t.Fatalf("checks = %d, want 3", checks)
	}
	if complaints != 4 {
		t.Fatalf("complaints = %d, want 4", complaints)
	}

	// пустой набор
	if c, comp := aggregateCounts(map[string]int{}); c != 0 || comp != 0 {
		t.Fatalf("empty: checks=%d complaints=%d", c, comp)
	}
}

func contains(list []string, s string) bool {
	for _, v := range list {
		if v == s {
			return true
		}
	}
	return false
}

func TestAllowedDatasetsForRole(t *testing.T) {
	// default (и пустая строка) — только public
	if got := allowedDatasetsForRole("default"); len(got) != 1 || !contains(got, "public") {
		t.Fatalf("default: %v", got)
	}
	if got := allowedDatasetsForRole(""); len(got) != 1 || !contains(got, "public") {
		t.Fatalf("empty role: %v", got)
	}
	// volunteer — public + volunteer_test, без dev_test
	got := allowedDatasetsForRole("volunteer")
	if len(got) != 2 || !contains(got, "public") || !contains(got, "volunteer_test") || contains(got, "dev_test") {
		t.Fatalf("volunteer: %v", got)
	}
	// admin — все слои
	if got := allowedDatasetsForRole("admin"); len(got) != 3 {
		t.Fatalf("admin: %v", got)
	}
}

func TestRateLimiter(t *testing.T) {
	rl := newRateLimiter(time.Hour)

	if !rl.allow("u1") {
		t.Fatal("первый запрос должен быть разрешён")
	}
	if rl.allow("u1") {
		t.Fatal("второй запрос в пределах интервала должен быть отклонён")
	}
	if !rl.allow("u2") {
		t.Fatal("другой ключ должен быть разрешён")
	}

	// после истечения интервала — снова разрешено
	rl.attempts["u1"] = time.Now().Add(-2 * time.Hour)
	if !rl.allow("u1") {
		t.Fatal("после истечения интервала запрос должен быть разрешён")
	}
}