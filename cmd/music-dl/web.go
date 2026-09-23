package main

import (
	"github.com/guohuiyuan/go-music-dl/internal/web"
	"github.com/spf13/cobra"
)

var port string
var noBrowser bool
var desktopMode bool
var basePath string

var webCmd = &cobra.Command{
	Use:   "web",
	Short: "Iniciar modo de serviço Web",
	Run: func(cmd *cobra.Command, args []string) {
		if desktopMode {
			web.StartDesktop(port)
			return
		}
		web.Start(port, !noBrowser, basePath)
	},
}

func init() {
	webCmd.Flags().StringVarP(&port, "port", "p", "8080", "Porta do serviço")
	webCmd.Flags().StringVar(&basePath, "base-path", web.DefaultRoutePrefix, "Caminho base da interface Web")
	webCmd.Flags().BoolVar(&noBrowser, "no-browser", false, "Não abrir o navegador automaticamente")
	webCmd.Flags().BoolVar(&desktopMode, "desktop", false, "Modo desktop embutido")
	_ = webCmd.Flags().MarkHidden("desktop")
	rootCmd.AddCommand(webCmd)
}
