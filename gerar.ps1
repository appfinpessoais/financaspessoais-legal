# Gera privacidade.html e termos.html a partir das notas 15 e 16 do Vault.
# Só a parte depois do "---" que separa as anotações internas do texto público é publicada.
# Uso: .\gerar.ps1   (ou .\gerar.ps1 -Vault "caminho\do\Vault")
param([string]$Vault = (Join-Path $PSScriptRoot "..\VaultAppFinancasPessoal"))

$utf8 = New-Object System.Text.UTF8Encoding($false)

function Converter-Inline([string]$t) {
    $t = $t.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
    $t = [regex]::Replace($t, '\*\*(.+?)\*\*', '<strong>$1</strong>')
    $t = [regex]::Replace($t, '\[\[(?:[^\]|]+\|)?([^\]]+)\]\]', '$1')
    $t = [regex]::Replace($t, '[\w.+-]+@[\w-]+(?:\.[\w-]+)+', '<a href="mailto:$0">$0</a>')
    return $t
}

function Converter-Nota([string]$arquivo) {
    $linhas = [IO.File]::ReadAllText($arquivo, $utf8) -split "`r?`n"
    # 1º e 2º "---" = frontmatter; 3º = fim das anotações internas.
    $seps = @(for ($i = 0; $i -lt $linhas.Length; $i++) { if ($linhas[$i].Trim() -eq '---') { $i } })
    if ($seps.Count -lt 3) { throw "Separador '---' não encontrado em $arquivo" }
    $corpo = $linhas[($seps[2] + 1)..($linhas.Length - 1)]

    $html = New-Object System.Collections.Generic.List[string]
    $titulo = ''
    $emLista = $false; $emTabela = $false; $cabecalho = $true
    $fechar = {
        if ($emLista) { $html.Add('</ul>'); Set-Variable emLista $false -Scope 1 }
        if ($emTabela) { $html.Add('</tbody></table></div>'); Set-Variable emTabela $false -Scope 1 }
    }
    foreach ($l in $corpo) {
        $s = $l.Trim()
        if ($s -eq '') { & $fechar; continue }
        if ($s -match '^\*\*([^*]+)\*\*$' -and -not $titulo) {
            & $fechar; $titulo = $Matches[1]; $html.Add("<h1>$(Converter-Inline $titulo)</h1>"); continue
        }
        if ($s -match '^## (.+)$') { & $fechar; $html.Add("<h2>$(Converter-Inline $Matches[1])</h2>"); continue }
        if ($s -match '^- (.+)$') {
            if ($emTabela) { & $fechar }
            if (-not $emLista) { $html.Add('<ul>'); $emLista = $true }
            $html.Add("<li>$(Converter-Inline $Matches[1])</li>"); continue
        }
        if ($s -match '^\|') {
            if ($s -match '^\|[\s|:-]+\|$') { continue }
            $celulas = $s.Trim('|').Split('|') | ForEach-Object { Converter-Inline $_.Trim() }
            if (-not $emTabela) {
                & $fechar; $emTabela = $true
                $html.Add('<div class="tabela"><table><thead><tr>' + (($celulas | ForEach-Object { "<th>$_</th>" }) -join '') + '</tr></thead><tbody>')
            } else {
                $html.Add('<tr>' + (($celulas | ForEach-Object { "<td>$_</td>" }) -join '') + '</tr>')
            }
            continue
        }
        & $fechar
        $classe = if ($s -like 'Vigente desde*') { ' class="vigencia"' } else { '' }
        $html.Add("<p$classe>$(Converter-Inline $s)</p>")
    }
    & $fechar
    return @{ Titulo = $titulo; Html = ($html -join "`n") }
}

function Montar-Pagina([string]$tituloAba, [string]$conteudo) {
    $modelo = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'modelo.html'), $utf8)
    return $modelo.Replace('{{TITULO}}', $tituloAba).Replace('{{CONTEUDO}}', $conteudo)
}

$paginas = @(
    @{ Nota = '15 - Política de privacidade.md'; Saida = 'privacidade.html'; Aba = 'Política de privacidade' },
    @{ Nota = '16 - Termos de uso.md'; Saida = 'termos.html'; Aba = 'Termos de uso' }
)
foreach ($p in $paginas) {
    $r = Converter-Nota (Join-Path $Vault $p.Nota)
    if ($p.Saida -eq 'termos.html') {
        # Nos termos, cada menção à política vira link para a página dela (fora dos títulos).
        $r.Html = [regex]::Replace($r.Html, '(?i)(?<!<h\d>[^<]*)\b(política de privacidade)\b', '<a href="privacidade.html">$1</a>')
    }
    $saida = Join-Path $PSScriptRoot $p.Saida
    [IO.File]::WriteAllText($saida, (Montar-Pagina "$($p.Aba) · Finanças Pessoais" $r.Html), $utf8)
    "Gerado: $($p.Saida) ($($r.Titulo))"
}
