package main

import (
	"testing"

	"github.com/guohuiyuan/go-music-dl/internal/web"
)

func TestWebBasePathFlagDefault(t *testing.T) {
	flag := webCmd.Flags().Lookup("base-path")
	if flag == nil {
		t.Fatal("o comando web está sem o --base-path")
	}
	if got, want := flag.DefValue, web.DefaultRoutePrefix; got != want {
		t.Fatalf("padrão do --base-path = %q, esperado %q", got, want)
	}
}
