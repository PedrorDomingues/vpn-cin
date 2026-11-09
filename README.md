# VPN CIn/UFPE — Fedora, Debian e Ubuntu

> **Aviso:** este script foi atualizado com o auxílio de inteligência artificial
> (IA). Use por sua conta e risco e revise o código antes de executá-lo.
> **Toda a implementação de autenticação, diagnóstico e verificação pelo
> terminal foi produzida 100% com uso de IA. O risco de uso é de quem executar.**
> Os testes executados pelo usuário não constituem auditoria de segurança.
> A conexão foi validada no Fedora 45 KDE e, via Docker, no Debian 13 e
> no Ubuntu 26.04.1 LTS, nos ambientes descritos abaixo.
> Isso não garante o funcionamento em todas as distribuições, versões ou redes.

Script Bash para instalar as dependências e criar ou atualizar o perfil
`VPN-CIn` no NetworkManager, usando strongSwan com IKEv2/EAP.

`vpn_cin.sh` configura o perfil. Para conectar, use o menu de rede do ambiente
gráfico ou o auxiliar `conectar_vpn.sh` pelo terminal. É necessário possuir
uma conta do CIn/UFPE com acesso à VPN.

## Compatibilidade

| Ambiente | Situação |
| --- | --- |
| Fedora 45 KDE | Scripts revisados revalidados: configuração, autenticação pelo terminal, DNS interno e HTTPS |
| Debian 13 | Scripts revisados revalidados via Docker: configuração, autenticação pelo terminal, DNS interno e HTTPS |
| Ubuntu 26.04.1 LTS | Scripts revisados revalidados via Docker: configuração, autenticação pelo terminal, DNS interno e HTTPS |
| Linux Mint e Pop!_OS | Ramo de instalação implementado; sem teste individual de conexão |
| Outras derivadas | Reconhecidas quando `ID_LIKE` contém `debian` ou `ubuntu`; dependem dos pacotes disponíveis |

Os testes Debian e Ubuntu usaram o kernel do Fedora e ajustes de rede e
autenticação próprios dos contêineres. Validaram a negociação VPN e o acesso
ao DNS interno, mas não equivalem a testes completos dos desktops. O auxiliar
de terminal é opcional e não está incorporado ao script principal.
Outras versões do Fedora não foram validadas individualmente.

### Ambientes e kernels dos testes

| Distribuição testada | Ambiente | Kernel observado |
| --- | --- | --- |
| Fedora 45 KDE | Host | `7.2.15-300.fc45.x86_64` |
| Debian 13 (contêiner identificado como 13.7) | Docker no mesmo host Fedora | `7.2.15-300.fc45.x86_64` (compartilhado com o host) |
| Ubuntu 26.04.1 LTS | Docker no mesmo host Fedora | `7.2.15-300.fc45.x86_64` (compartilhado com o host) |

As versões acima foram consultadas com `uname -r` em 09/11/2026. Os contêineres
não executam kernels Debian ou Ubuntu próprios: os testes validam os pacotes
e as configurações dessas distribuições sobre o kernel Fedora. Não houve
validação em instalações Debian ou Ubuntu com kernels próprios.

## Requisitos

- Bash, acesso à Internet e repositórios da distribuição habilitados.
- `sudo` para executar como usuário comum, ou execução como root.
- NetworkManager em execução e gerenciando uma conexão de rede utilizável.
- Ambiente gráfico com integração de VPN e agente de senhas, ou o auxiliar de terminal.
- Todas as VPNs controladas pelo NetworkManager desconectadas ao configurar.

O script instala NetworkManager caso falte, mas não o inicia nem converte
automaticamente uma rede gerenciada por outro serviço. O diagnóstico usa
`journalctl`; `resolvectl` é consultado quando disponível.

## Instalação e uso

Baixe `vpn_cin.sh`, abra um terminal na pasta do arquivo e execute como seu
usuário habitual:

```bash
bash vpn_cin.sh
```

Informe as iniciais do CIn, sem e-mail.

Para informar o login diretamente:

```bash
bash vpn_cin.sh --login SEU_LOGIN
```

Depois, selecione **VPN-CIn** no menu de rede do desktop e informe a senha da
VPN. A senha fica configurada para ser solicitada a cada conexão. Para mudar
essa política, utilize o editor de conexões do ambiente gráfico.

No Fedora KDE, se o plugin acabou de ser instalado e a opção não aparecer,
saia da sessão e entre novamente. Se o serviço VPN ainda não for encontrado,
reinicie o computador em um momento conveniente.

Para desconectar, use o menu de rede ou:

```bash
nmcli connection down id VPN-CIn
```

## Conectar pelo terminal (Fedora, Debian e Ubuntu)

O auxiliar `conectar_vpn.sh` usa o mesmo código para as três distribuições.
Ele verifica se o perfil é único, usa strongSwan/EAP e tem `password-flags=2`.
Baixe os dois scripts para a mesma pasta. Primeiro configure o perfil com
o script principal e depois conecte:

```bash
bash vpn_cin.sh
bash conectar_vpn.sh
```

Execute como seu usuário habitual, com permissão para ativar a conexão no
NetworkManager. No pedido `Senha da VPN CIn`, digite a **senha da conta do CIn**;
ela não aparece na tela. Nas próximas conexões, basta executar
`bash conectar_vpn.sh`; não é necessário refazer a configuração.
Para um perfil com outro nome:

```bash
bash conectar_vpn.sh 'NOME-DO-PERFIL'
```

O auxiliar evita o erro GTK `cannot open display`. Ele fornece ao `nmcli`
metadados temporários do plugin e um adaptador `external-ui` sem interface
gráfica, através de `NM_VPN_PLUGIN_DIR`. Os arquivos instalados pela
distribuição e o diálogo gráfico do desktop permanecem intactos.

A senha passa pelo campo `vpn.secrets.password` em arquivo temporário com
permissão `0600`, dentro de um diretório `0700`. Não é gravada no perfil nem
passada em argumentos de processos. Os arquivos temporários são removidos
ao terminar, inclusive em interrupções tratadas pelo script. O diretório
temporário pode permanecer após `SIGKILL` ou queda de energia; não há promessa
de apagamento seguro do conteúdo em disco. O diretório temporário precisa
permitir a execução do adaptador; o script prefere
`XDG_RUNTIME_DIR` e usa `TMPDIR` ou `/tmp` como alternativas.

Esse auxiliar é destinado ao método EAP por senha do perfil criado por este
projeto. Ele não implementa autenticação multifator, certificados de cliente
ou instalação de infraestrutura Docker. O NetworkManager deve ter uma
conexão de base gerenciada e ativa antes de iniciar a VPN.

O auxiliar consolidado e revisado foi usado na revalidação autenticada dos
três ambientes. Também passou por teste isolado com senha fictícia e destino
localhost, verificando a entrega do segredo, o início da negociação IKEv2 e
a limpeza dos arquivos temporários sem alterar o plugin instalado.

Para desconectar:

```bash
nmcli connection down id VPN-CIn
```

## Opções

| Opção | Efeito |
| --- | --- |
| `--login LOGIN` | Define as iniciais sem perguntar interativamente |
| `--force-encap` | Força encapsulamento ESP em UDP |
| `--diagnostico` | Consulta estado, perfil, DNS e logs recentes, sem configurar a VPN |
| `--help` | Exibe a ajuda |

Use `--force-encap` somente para testar redes que filtram ESP:

```bash
bash vpn_cin.sh --login SEU_LOGIN --force-encap
```

Essa opção não corrige senha, certificado ou bloqueio de UDP 500/4500.
Uma nova execução sem a opção volta a configurar `encap=no`.

## Dependências instaladas

O script verifica os pacotes instalados e solicita apenas os ausentes.

### Fedora

- `NetworkManager`
- `NetworkManager-strongswan`
- `strongswan-charon-nm`
- `NetworkManager-strongswan-gnome`
- `ca-certificates`
- `p11-kit-trust`
- `openssl`
- `policycoreutils` (comando `restorecon`)
- `procps-ng` (comandos `pgrep` e `pkill`)
- `plasma-nm-strongswan`, quando `plasma-nm` já está instalado

A instalação usa `dnf install -y`.

### Debian, Ubuntu e derivadas

- `network-manager`
- `network-manager-strongswan`
- `libstrongswan-extra-plugins`
- `libcharon-extra-plugins`
- `ca-certificates`
- `libcharon-extauth-plugins`, quando disponível nos repositórios

O backend `strongswan-nm` é instalado como dependência de
`network-manager-strongswan`. No Debian 13, EAP-MSCHAPv2 está em
`libcharon-extauth-plugins`; em versões anteriores, ele integrava
`libcharon-extra-plugins`.

O script executa `apt-get update` em cada configuração para identificar a
disponibilidade do pacote separado e usa `apt-get install -y` para os ausentes.

## Alterações em relação ao original

Comparação com `vpn_cin(1).sh`, cujo cabeçalho informa 21/11/2025.

| Aspecto | Original | Versão atual |
| --- | --- | --- |
| Distribuições | Comandos APT/dpkg | Fedora/dnf e família Debian/APT, incluindo `ID_LIKE` |
| Dependências | Dois pacotes declarados | Gerenciador, backend por dependência, plugins e integração gráfica |
| EAP-MSCHAPv2 no Debian 13 | Dependência separada não declarada | Inclui `libcharon-extauth-plugins` quando disponível |
| Perfil existente | Excluía o perfil e arquivos correspondentes | Atualiza por UUID e preserva propriedades adicionais |
| Nomes duplicados | Sem proteção específica | Interrompe se houver múltiplos perfis `VPN-CIn` |
| Tipo do perfil | Recriava o perfil | Recusa atualizar um perfil de outro backend |
| Interface | `cin-ipsec-ike2` | Sem interface fixa, inclusive ao atualizar um perfil antigo |
| Senha | `password-flags=1` | `password-flags=2`, pedir ao conectar |
| Entrada | Login sem validação | Valida caracteres e aceita `--login` |
| Fedora | Sem tratamento | CA GlobalSign R46 e prioridade GMP |
| Diagnóstico | Mensagem final | Opção para consultar estado e logs |
| Erros | Verificação pontual da instalação | Modo estrito Bash e indicação da linha de falha |

Foram mantidos o nome do perfil, servidor, método EAP, IP virtual, algoritmos,
DNS, domínios de busca, autoconexão desativada e IPv6 desabilitado no perfil.
O script não implementa rollback: uma falha posterior pode deixar pacotes ou
arquivos já instalados.

### Correções incluídas na versão revalidada

- Remove a interface fixa também de perfis antigos que são atualizados.
- Verifica VPNs ativas antes de instalar pacotes e novamente antes de configurar.
- Verifica uma versão candidata instalável de `libcharon-extauth-plugins`.
- Declara explicitamente CAs no Debian e as ferramentas SELinux/processos no Fedora.
- O diagnóstico continua mesmo se `resolvectl` ou a consulta ao journal falhar.
- O auxiliar usa UUID, valida o tipo de autenticação e trata caminhos temporários
  com caracteres especiais sem interpretá-los como substituições `sed`.

Após essas correções, a mesma versão dos dois scripts
foi revalidada com autenticação real no Fedora, Debian e Ubuntu. Os resultados
foram confirmados pelo usuário em 09/11/2026. A sintaxe Bash, o ShellCheck e
os testes de regressão isolados também passaram.

## Configuração aplicada

| Campo | Valor |
| --- | --- |
| Perfil | `VPN-CIn` |
| Gateway | `vpn.cin.ufpe.br` |
| Backend | `org.freedesktop.NetworkManager.strongswan` |
| Autenticação | EAP |
| IKE e ESP | `aes256-sha256-modp2048` |
| DNS | `172.21.2.151`, `172.21.2.152`, `172.21.2.153` |
| Domínios de busca | `cin.ufpe.br`, `windows.cin.ufpe.br` |
| IPv6 | Desabilitado somente no perfil VPN |

Rotas e seletores de tráfego são negociados com o servidor. O script não
promete uma política específica de túnel completo ou dividido.

### Tratamento específico do Fedora

A CA GlobalSign Root R46 é extraída do repositório de confiança local.
O script verifica a impressão SHA-256 e se a CA não está expirada antes de instalá-la em:

```text
/etc/pki/tls/certs/vpn-cin-globalsign-r46.pem
```

Também instala:

```text
/etc/strongswan/strongswan.d/vpn-cin-compat.conf
```

Esse arquivo define prioridade `load = 2` para o plugin GMP do `charon-nm`,
usada na configuração validada para compatibilidade com assinaturas RSA
antigas. O ajuste afeta todas as VPNs strongSwan gerenciadas pelo NetworkManager.
A política criptográfica global do Fedora não é alterada.

Uma configuração anterior diferente é preservada na primeira cópia
`vpn-cin-compat.conf.antes-vpn-cin`. Os contextos SELinux são restaurados com
`restorecon`. Sem VPNs NM ativas, o script encerra o backend `charon-nm`, caso
esteja em execução; ele será reaberto na próxima conexão.

Debian e Ubuntu não recebem esses dois arquivos. Utilizam a confiança
disponível no backend, preservando uma CA explicitamente configurada em um
perfil existente. Não é necessário distribuir um arquivo PEM separado.

## Verificação e diagnóstico

Depois de conectar pela interface gráfica ou pelo auxiliar de terminal:

```bash
nmcli connection show --active
getent ahostsv4 cin.ufpe.br
```

Teste também o serviço interno que você precisa acessar. No teste Debian 13,
o DNS interno `172.21.2.151` respondeu com `172.21.0.54` para `cin.ufpe.br`.
Endereços podem mudar; essa resposta isolada não valida todos os serviços.

Na revalidação da versão revisada, os três ambientes passaram pela
configuração do perfil, autenticação pelo `conectar_vpn.sh`, consulta ao DNS
interno e acesso HTTPS com validação TLS. Debian e Ubuntu foram executados
via Docker. O roteiro de revalidação era local e não é necessário para usar
os scripts deste repositório.

No Ubuntu 26.04.1 LTS, em 09/11/2026, foram confirmados:

- Instalação das dependências pelo script e criação/atualização do perfil.
- Ativação da VPN com autenticação EAP.
- Resposta DNS `NOERROR` de `172.21.2.151`, resolvendo `cin.ufpe.br` para `172.21.0.54`.
- Acesso HTTPS a esse endereço usando `curl --resolve`, com resposta `HTTP/2 301`
  e redirecionamento para `https://portal.cin.ufpe.br/`.

Os testes de revalidação consultaram diretamente o DNS interno e usaram
`curl --resolve` com o IP obtido. Eles não validam a aplicação automática dos
DNS ao resolvedor padrão do sistema, nem o acesso a todos os serviços do CIn.

Logo após uma falha de conexão:

```bash
bash vpn_cin.sh --diagnostico
sudo journalctl -b _COMM=charon-nm --since '-15 minutes' --no-pager
```

O acesso aos logs depende das permissões da sessão. Revise login e endereços
antes de compartilhar a saída.

`Could not find source connection` indica que é preciso verificar a conexão
de rede base no NetworkManager. `cannot open display` indica que o diálogo de
senha tentou abrir sem uma sessão gráfica; o uso sem interface gráfica exige
o auxiliar `conectar_vpn.sh` documentado acima.

## Publicação e manutenção

O repositório mantém todos os arquivos na raiz:

- `vpn_cin.sh`: instalação das dependências e configuração do perfil.
- `conectar_vpn.sh`: autenticação opcional pelo terminal, comum às três distros.
- `README.md`: instruções, alterações e resultados dos testes.
- `.gitignore`: exclusões para credenciais, perfis exportados e logs locais.

Não publique credenciais, perfis exportados com segredos ou logs pessoais.

Não foi adicionada uma licença: confirme a origem e as permissões do script
original antes de escolher a licença para o repositório.

A configuração foi revisada em novembro de 2026. Se o CIn alterar o gateway,
a cadeia de certificados ou os algoritmos, revise os valores no script.
A verificação de CA no Fedora interrompe a configuração se a raiz esperada
estiver ausente, diferente ou expirada.
