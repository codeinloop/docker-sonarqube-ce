# SonarQube Community + Branch Plugin

SonarQube Community Build com o [Community Branch Plugin](https://github.com/mc1arke/sonarqube-community-branch-plugin)
(analise de branches e decoracao de Pull Request, que a edicao Community nao traz),
PostgreSQL, metadados para o [Arcane](https://getarcane.app) e DNS via [DockRoute](https://dockroute.dev).

Dominio: **https://sonar.codeinloop.net**

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

`dockroute.tunnel.service` aponta para `http://sonarqube:9000`, que e a origem vista de dentro
da rede docker. Ou seja, o `cloudflared` precisa estar nessa rede:

```bash
docker network connect sonarnet <container-do-cloudflared>
```

Por isso a rede tem `name: sonarnet` fixo, sem o prefixo do projeto.
Com o tunnel ativo, `dockroute.type` e `dockroute.target` sao ignorados.

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
| Dominio publico | labels `dockroute.*` | DockRoute publica `sonar.codeinloop.net` via Cloudflare Tunnel |

## Upgrade de versao

Altere **as duas** variaveis juntas em `.env` (`SONARQUBE_VERSION` e `PLUGIN_VERSION`,
sempre no mesmo major.minor) e rode `docker compose up -d --build`.

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
