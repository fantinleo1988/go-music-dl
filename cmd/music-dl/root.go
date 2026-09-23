package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/guohuiyuan/go-music-dl/core"
	"github.com/guohuiyuan/go-music-dl/internal/cli"
)

// Variáveis de configuração globais
var (
	showVersion bool
	keyword     string
	urlStr      string
	sources     []string
	outDir      string
	withCover   bool
	withLyrics  bool
)

var rootCmd = &cobra.Command{
	Use:   "music-dl",
	Short: "Ferramenta agregadora de busca e download de músicas (Suporta múltiplas fontes/TUI/Web/Capa/Letra)",
	Long: `O Go Music DL é uma ferramenta agregadora de busca e download de músicas baseada em linha de comando.

Fontes de música suportadas:
  - netease   (NetEase Cloud Music)
  - qq        (QQ Music)
  - kugou     (KuGou Music)
  - kuwo      (KuWo Music)
  - migu      (MiGu Music)
  - qianqian  (QianQian Music)
  - soda      (Soda Music)
  - fivesing  (5sing Original)
  - ... e também jamendo, joox, bilibili, etc.

Recursos:
  - Interface interativa TUI, suporta múltipla seleção com a barra de espaço
  - Interface versão Web (inicie usando 'music-dl web')
  - Suporta download de áudio de alta qualidade (algumas fontes suportam lossless)
  - Download automático de imagem de capa (necessário ativar --cover)
  - Download automático de letras LRC (necessário ativar --lyrics)`,
	Example: `  # 1. Busca básica (busca em todas as fontes por padrão)
  music-dl -k "周杰伦"

  # 2. Busca em fontes específicas (exemplo: buscar apenas no NetEase e QQ)
  music-dl -k "林俊杰" -s netease,qq

  # 3. Download completo (diretório específico + capa + letras)
  music-dl -k "陈奕迅" -o "MyMusic" --cover --lyrics

  # 4. Iniciar a interface Web
  music-dl web

  # 5. Entrar diretamente no modo interativo TUI (sem parâmetros)
  music-dl`,
	Run: func(cmd *cobra.Command, args []string) {
		if showVersion {
			fmt.Printf("music-dl version v%s (TUI Version)\n", core.AppVersion)
			return
		}

		// [Correção] O diretório padrão foi definido como "downloads" em vez de "."
		if outDir == "" {
			outDir = "downloads"
		}

		// Garante que o diretório exista
		if _, err := os.Stat(outDir); os.IsNotExist(err) {
			_ = os.MkdirAll(outDir, 0755)
		}

		// Se houver uma URL (funcionalidade incompleta, mantendo o aviso por enquanto)
		if urlStr != "" {
			fmt.Println("🚀 Funcionalidade de download por URL em desenvolvimento: ", urlStr)
			return
		}

		// Inicia a interface TUI
		cli.StartUI(keyword, sources, outDir, withCover, withLyrics)
	},
}

func init() {
	// Vincula as Flags
	rootCmd.Flags().BoolVarP(&showVersion, "version", "v", false, "Mostrar informações da versão")
	rootCmd.Flags().StringVarP(&keyword, "keyword", "k", "", "Palavra-chave de busca")
	rootCmd.Flags().StringVarP(&urlStr, "url", "u", "", "Fazer download da música através de uma URL específica (em desenvolvimento)")

	// [Otimização] Indicar claramente as fontes disponíveis
	rootCmd.Flags().StringSliceVarP(&sources, "sources", "s", []string{}, "Especificar fontes de busca, separadas por vírgula (ex: netease,qq,kugou)")

	rootCmd.Flags().StringVarP(&outDir, "outdir", "o", "data/downloads", "Especificar diretório de download")
	rootCmd.Flags().BoolVar(&withCover, "cover", true, "Fazer o download da imagem de capa simultaneamente (ativado por padrão, use --cover=false para desativar)")
	rootCmd.Flags().BoolVarP(&withLyrics, "lyrics", "l", true, "Fazer o download da letra simultaneamente (ativado por padrão, use --lyrics=false para desativar)")
}
