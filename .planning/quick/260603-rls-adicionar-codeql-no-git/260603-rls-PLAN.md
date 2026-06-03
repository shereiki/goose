---
phase: quick
plan: 260603-rls
type: execute
wave: 1
depends_on: []
files_modified:
  - .github/workflows/codeql.yml
autonomous: true
requirements: [SECURITY-CODEQL]

must_haves:
  truths:
    - "CodeQL analisa Swift (GooseSwift/) em cada push/PR para main"
    - "CodeQL analisa Python (server/) em cada push/PR para main"
    - "Scan semanal agendado corre independentemente de pushes"
    - "Resultados aparecem no separador Security → Code scanning do repositório GitHub"
  artifacts:
    - path: ".github/workflows/codeql.yml"
      provides: "Workflow CodeQL com análise Swift e Python"
      contains: "github/codeql-action"
  key_links:
    - from: ".github/workflows/codeql.yml"
      to: "github/codeql-action/init@v3"
      via: "uses"
      pattern: "codeql-action/init"
    - from: ".github/workflows/codeql.yml"
      to: "github/codeql-action/analyze@v3"
      via: "uses"
      pattern: "codeql-action/analyze"
---

<objective>
Adicionar CodeQL ao pipeline CI do GitHub Actions para análise estática de segurança em Swift e Python.

Purpose: Complementar o Trivy (vulnerabilidades de dependências + secrets) e o cargo-audit (RustSec) com análise de fluxo de dados e padrões de segurança no código fonte da app iOS (Swift) e do servidor (Python). CodeQL é gratuito para repositórios públicos via github/codeql-action.

Output: `.github/workflows/codeql.yml` com dois jobs paralelos — um para Swift, outro para Python — que correm em push/PR para main e num schedule semanal.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.github/workflows/security.yml
</context>

<tasks>

<task type="auto">
  <name>Task 1: Criar workflow CodeQL para Swift e Python</name>
  <files>.github/workflows/codeql.yml</files>
  <action>
Criar `.github/workflows/codeql.yml` com as seguintes características:

Triggers:
- `push` para `main` (sem filtro de paths — alterações de código devem sempre disparar análise)
- `pull_request` para `main` (sem filtro de paths)
- `schedule`: cron `"0 8 * * 1"` (segundas-feiras às 08:00 UTC — escalonado face ao security.yml que corre às 07:00)
- `workflow_dispatch`

Permissions mínimas (per D-princípio de menor privilégio):
```
permissions:
  contents: read
  security-events: write  # obrigatório para upload de resultados SARIF
  actions: read            # obrigatório para github/codeql-action em repositórios privados
```

Strategy matrix com dois targets: `language: [swift, python]`

Cada job usa `runs-on: macos-15` para Swift (CodeQL Swift requer macOS com Xcode; Python pode correr em ubuntu mas a matrix simplifica a config) — na verdade usar `runs-on: ${{ matrix.language == 'swift' && 'macos-15' || 'ubuntu-latest' }}` para eficiência de custos.

Steps de cada job:
1. `actions/checkout@v4`
2. `github/codeql-action/init@v3` com `languages: ${{ matrix.language }}` e `queries: security-extended` (cobre OWASP Top 10 e padrões iOS/Python específicos)
3. Para Swift: step de build com `xcodebuild -project GooseSwift.xcodeproj -scheme GooseSwift -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO` — CodeQL Swift requer compilação real para análise precisa de fluxo de dados. Para Python: sem build step (CodeQL analisa Python sem compilação)
4. `github/codeql-action/analyze@v3` com `category: "/language:${{ matrix.language }}"` e `output: sarif-results` — os resultados SARIF são enviados automaticamente para o separador Security → Code scanning

Adicionar no cabeçalho do ficheiro um comentário de bloco (estilo do security.yml existente) a explicar o âmbito:
- swift: GooseSwift/ — análise de fluxo de dados, injeção, uso inseguro de APIs iOS
- python: server/ — injeção SQL, path traversal, desserialização insegura, uso de crypto fraco

Não analisar Rust: suporte CodeQL experimental, memória gerida pelo compilador, cargo-audit cobre advisories conhecidos.
  </action>
  <verify>
    <automated>grep -c "codeql-action/analyze" /Users/francisco/Documents/goose/.github/workflows/codeql.yml</automated>
  </verify>
  <done>
Ficheiro `.github/workflows/codeql.yml` existe com matrix para swift e python, usa github/codeql-action/init@v3 e github/codeql-action/analyze@v3, tem schedule semanal, e inclui step de build xcodebuild para o job Swift.
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| GitHub Actions runner → github/codeql-action | Action de terceiro (GitHub-owned) executa código no runner |
| SARIF results → GitHub Security tab | Resultados enviados para API GitHub via token automático |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-codeql-01 | Tampering | github/codeql-action@v3 | mitigate | Pinned a major version tag `@v3` (GitHub mantém integridade dos tags de versão major para as suas próprias actions) |
| T-codeql-02 | Information Disclosure | SARIF upload | accept | Resultados vão para o separador Security privado do repositório — acesso restrito a colaboradores com permissão de segurança |
| T-codeql-SC | Tampering | npm/pip/cargo installs | accept | Workflow não instala pacotes externos — usa apenas actions pinadas e xcodebuild do sistema |
</threat_model>

<verification>
Após push do workflow para main:
1. Verificar no separador Actions que o workflow "CodeQL" aparece e corre sem erro de sintaxe
2. Verificar no separador Security → Code scanning que resultados aparecem para swift e python
3. Confirmar que o job Swift usa macos-15 e o Python usa ubuntu-latest
</verification>

<success_criteria>
- `.github/workflows/codeql.yml` existe e é YAML válido
- Workflow tem dois jobs na matrix: swift e python
- Cada job faz init → (build para swift) → analyze com github/codeql-action/analyze@v3
- Schedule semanal configurado (segunda-feira)
- Resultados SARIF enviados para GitHub Security tab (permission security-events: write presente)
</success_criteria>

<output>
Criar `.planning/quick/260603-rls-adicionar-codeql-no-git/260603-rls-SUMMARY.md` quando concluído.
</output>
