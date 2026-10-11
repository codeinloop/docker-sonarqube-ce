# SonarQube Community + Branch Plugin

SonarQube Community Build com o [Community Branch Plugin](https://github.com/mc1arke/sonarqube-community-branch-plugin)
(analise de branches e decoracao de Pull Request, que a edicao Community nao traz),
PostgreSQL, [SonarQube MCP Server](https://docs.sonarsource.com/sonarqube-mcp-server/) para
agentes de IA, metadados para o [Arcane](https://getarcane.app) e DNS via [DockRoute](https://dockroute.dev).

Os dominios vem do `.env` (`SONAR_DOMAIN` e `MCP_DOMAIN`). Nos exemplos deste README eles
aparecem como `sonar.example.com` e `mcp.sonar.example.com`: troque pelos seus.

## Subir

A imagem `sonarqube-ce-branch` e construida localmente e **nao existe em nenhum registry**.
Por isso o servico declara `pull_policy: build`.

No Arcane, alem disso:

1. Use **Build & Deploy** (o botao **Up** sozinho nao roda o build).
2. Deixe a **Pull policy do deploy em "never pull"**. Com "pull if not present" ou
   "always pull latest", o Arcane tenta baixar a imagem antes de subir e falha com
   `pull access denied for sonarqube-ce-branch`. Essa configuracao fica lembrada
   entre deploys.

Se preferir que o Arcane so faca pull, publique a imagem num registry (ex.: o Container
Registry do proprio GitLab) e troque o `image:` pelo endereco publicado.

Local, para comparar:

```bash
cp .env.example .env   # ajuste POSTGRES_PASSWORD
docker compose up -d --build
```

Primeiro boot leva ~2-3 min (migracao do banco + Elasticsearch). Login inicial: `admin` / `admin`.

## Cloudflare Tunnel

O `cloudflared` alcanca o SonarQube **pelo nome do container**, entao os dois precisam
compartilhar uma rede. Em vez de `docker network connect` na mao (que se perde quando um
dos containers e recriado), o SonarQube entra declarativamente nas duas redes:

| Rede | Quem esta nela | Para que |
|---|---|---|
| `sonarnet` (`internal: true`) | sonarqube + db + mcp | trafego do banco e do MCP com o SonarQube, sem rota para fora |
| `dockroute_default` (`external`) | sonarqube + mcp + cloudflared | origem do tunnel |

O **banco fica fora** da rede compartilhada: de dentro dela o host `db` nem resolve.

A rede externa precisa existir antes do deploy (ela e criada pelo stack do dockroute/cloudflared).
O nome dela vem de `DOCKROUTE_NETWORK` no `.env` (padrao `dockroute_default`).

Com isso, `dockroute.tunnel.service: "http://sonarqube:9000"` resolve do lado do cloudflared.
O MCP segue a mesma regra, com hostname proprio: `dockroute.tunnel.service: "http://sonarqube-mcp:8080"`.

A porta `9000` fica publicada apenas em `127.0.0.1`, ou seja, so acessivel de dentro do
host. A porta de entrada externa e o tunnel. Para liberar acesso direto na rede (util no
primeiro acesso, antes do tunnel existir), use `SONAR_BIND=0.0.0.0` no `.env`.

## Como as pecas se encaixam

| Peca | Onde | Por que |
|---|---|---|
| Branch plugin | `Dockerfile` | JAR + `web/` substituido; carregado como `-javaagent` nos processos **web** e **ce** |
| PostgreSQL UTF-8 | `compose.yaml` -> `POSTGRES_INITDB_ARGS` | requisito da [doc oficial](https://docs.sonarsource.com/sonarqube-server/10.8/setup-and-upgrade/install-the-server/installing-the-database) |
| `vm.max_map_count` | servico `sysctl` | o Elasticsearch embarcado nao sobe com o limite padrao |
| Icone/tags/links | bloco `x-arcane` + labels `arcane.*` | aparencia do projeto e dos servicos no Arcane |
| Dominio publico | labels `dockroute.*` | DockRoute publica `sonar.example.com` via Cloudflare Tunnel |
| MCP Server | servico `mcp` | imagem oficial `sonarsource/sonarqube-mcp` em modo HTTP; endpoint `https://mcp.sonar.example.com/mcp` |

## Upgrade de versao

Altere **as duas** variaveis juntas em `.env` (`SONARQUBE_VERSION` e `PLUGIN_VERSION`,
sempre no mesmo major.minor) e rode `docker compose up -d --build`.

O MCP tem ciclo proprio: `MCP_VERSION` segue as tags `1.x.y.z` da imagem
[`sonarsource/sonarqube-mcp`](https://hub.docker.com/r/sonarsource/sonarqube-mcp/tags) e nao
precisa casar com a versao do SonarQube (requisito minimo: Community Build 25.1+).

## Como o plugin convive com o volume de extensions

`extensions/` **e** um volume, para nao perder plugins instalados pelo Marketplace da
interface. O problema classico disso e que o JAR do branch plugin tambem mora ai dentro:
o volume, criado no primeiro boot, mascararia o JAR novo a cada upgrade e o SonarQube
subiria com um plugin de versao errada.

A saida esta no `entrypoint.sh`: o JAR vive em `plugin-dist/`, que fica **na imagem, fora
do volume**, e e reinstalado por cima de `extensions/plugins/` a cada start. Quem manda na
versao do plugin e sempre a imagem; o volume so guarda o resto.

Nada de dado real depende disso: projetos, analises, issues, usuarios e configuracoes
vivem no PostgreSQL. `conf/` nao e volume porque tudo que iria no `sonar.properties` esta
como variavel de ambiente no compose.

## Analisar uma branch / PR

```bash
# branch
sonar-scanner -Dsonar.branch.name=feature/minha-branch

# pull request (nunca junto com sonar.branch.*)
sonar-scanner \
  -Dsonar.pullrequest.key=123 \
  -Dsonar.pullrequest.branch=feature/minha-branch \
  -Dsonar.pullrequest.base=main
```

A branch alvo precisa ter sido analisada antes da PR.

## MCP Server (agentes de IA)

A [doc oficial](https://docs.sonarsource.com/sonarqube-mcp-server/setup/sonarqube-server-hosted)
descreve o MCP **hospedado pelo proprio SonarQube**: as propriedades `sonar.mcp.enabled` /
`sonar.mcp.serverUrl` fazem o servidor fazer proxy em `<sonar>/mcp`. Isso existe **so nas
edicoes comerciais** (Developer, Enterprise, Data Center). O Community Build nao tem essas
propriedades: o `sonar.properties` dele nao as declara e o codigo-fonte nao as conhece.

A saida e o modo **self-hosted HTTP** do mesmo MCP Server, que suporta Community Build:

- O servico `mcp` roda a imagem oficial `sonarsource/sonarqube-mcp` com `SONARQUBE_TRANSPORT=http`
  e fala com o SonarQube por `http://sonarqube:9000` dentro da `sonarnet`.
- O DockRoute publica o container em **`https://mcp.sonar.example.com`**. O TLS fica por conta
  do Cloudflare Tunnel, que e o que a doc pede para ambientes fora do localhost.
- O servidor e **stateless e sem token proprio**: cada agente envia o seu *user token* no header
  `Authorization: Bearer ...`. Permissoes e auditoria sao as do usuario dono do token.
- Na porta local, `8080` fica em loopback (`MCP_BIND`/`MCP_PORT` no `.env`), como o `9000`.

### Conectar um agente

1. No SonarQube: **My Account > Security > Generate Token**, tipo **User Token** (project/global
   token nao funciona com o MCP).
2. Claude Code:

```bash
claude mcp add --transport http sonarqube https://mcp.sonar.example.com/mcp \
  --header "Authorization: Bearer <seu-user-token>"
```

   Qualquer cliente MCP com transporte HTTP usa o mesmo formato:

```json
{
  "mcpServers": {
    "sonarqube": {
      "type": "http",
      "url": "https://mcp.sonar.example.com/mcp",
      "headers": { "Authorization": "Bearer <seu-user-token>" }
    }
  }
}
```

   O [gerador de configuracao](https://mcp.sonarqube.com/config-generator.html) da Sonar monta
   isso para cada IDE/CLI: escolha **SonarQube Server** e **Remote server (HTTP)**.

3. Reinicie o agente e rode `/mcp` para ver as tools (`search_sonar_issues_in_projects`,
   `get_project_quality_gate_status`, `show_rule`...).

Headers opcionais por cliente: `SONARQUBE_READ_ONLY: true` (bloqueia transicoes de issue) e
`SONARQUBE_TOOLSETS: issues,quality-gates` (reduz as tools expostas). Eles so restringem,
nunca ampliam.

### Verificar

```bash
curl -s https://mcp.sonar.example.com/info     # {"version":"1.28.0"}
curl -s -o /dev/null -w '%{http_code}\n' https://mcp.sonar.example.com/health   # 200
docker compose logs -f mcp
```

`/health` e `/info` nao exigem autenticacao; `/mcp` sem Bearer responde 401.

Limitacao: as tools de analise local (Sonar Vortex / `analyze_code_snippet`) precisam de acesso
ao sistema de arquivos do agente e nao funcionam com o MCP remoto. Para isso, rode a imagem em
modo `stdio` na sua maquina, conforme os quickstarts da doc.
