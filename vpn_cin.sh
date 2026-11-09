#!/usr/bin/env bash
# Configuração da VPN CIn/UFPE IKEv2 via NetworkManager/strongSwan.
# AVISO: toda a parte de autenticação, diagnóstico e verificação pelo terminal
# deste projeto foi produzida 100% com uso de IA. Revise antes de executar.
# O uso é por conta e risco de quem executar; não há garantia de funcionamento.
# Origem da comparação: vpn_cin(1).sh, datado de 21/11/2025.
# Revisão de compatibilidade: 09/11/2026. Consulte README.md.
#
# PRINCIPAIS MUDANÇAS EM RELAÇÃO AO ORIGINAL:
# - Suporte a Fedora/dnf e derivadas Debian/Ubuntu identificadas por ID_LIKE.
# - Dependências explícitas do NetworkManager, backend e plugins EAP/cripto.
# - Detecção de libcharon-extauth-plugins (EAP-MSCHAPv2 no Debian 13).
# - No Fedora: CA GlobalSign R46 verificada e prioridade GMP para RSA legado.
# - Atualização do perfil por UUID, sem excluir arquivos de conexões.
# - Interface livre (ifname '*') e senha solicitada ao conectar (flags=2).
# - Validação do login, interrupção em erros, diagnóstico e --force-encap.
#
# O script instala/configura; não conecta, não solicita a senha da VPN e não
# comprova acesso aos serviços internos. O uso principal é pelo desktop.
# Os auxiliares de autenticação e rede usados no teste Docker não fazem parte
# desta configuração. Não é necessário distribuir um certificado PEM separado.

# Interrompe comandos que falham, referências a variáveis não definidas e
# pipelines com falha; -E propaga o trap ERR a funções e subshells.
# Não há rollback automático: pacotes/arquivos já instalados podem permanecer.
set -Eeuo pipefail
trap 'printf "Erro na linha %s. Configuração não concluída.\n" "$LINENO" >&2' ERR
VPN_NAME=VPN-CIn
# Padrão mantido do original: não forçar encapsulamento ESP em UDP.
encap=no
login=''
ca_path=''
temp_dir=''
# Remove apenas o diretório temporário criado por esta execução.
trap '[[ -z $temp_dir ]] || rm -rf -- "$temp_dir"' EXIT
usage() {
  cat <<'HELP'
Uso: bash vpn_cin.sh [--login LOGIN] [--force-encap]
     bash vpn_cin.sh --diagnostico
Instala dependências e cria/atualiza VPN-CIn sem conectar.
No Fedora, instala a CA GlobalSign R46 do repositório de confiança local
e a compatibilidade RSA/GMP usada com sucesso no Fedora 45.
Execute com as VPNs desconectadas. A senha é solicitada ao conectar.
--force-encap: força ESP sobre UDP para testar redes que filtram ESP.
Não resolve bloqueio de UDP 500/4500 nem erro de autenticação.
--diagnostico: consulta estado e logs, sem modificar a rede.
HELP
}
# Opções de consulta são processadas antes de pedir login ou instalar pacotes.
# Diagnóstico pressupõe nmcli/journalctl disponíveis e acesso aos logs.
while (($#)); do
  case "$1" in
    --login)
      [[ $# -ge 2 && -n $2 ]] || { echo 'Informe o login.' >&2; exit 2; }
      login=$2; shift 2 ;;
    --force-encap) encap=yes; shift ;;
    --diagnostico)
      echo 'Diagnóstico de terminal produzido 100% com IA. Uso por sua conta e risco.'
      command -v nmcli >/dev/null || { echo 'nmcli não instalado.' >&2; exit 1; }
      nmcli general status
      nmcli -f NAME,UUID,TYPE connection show
      nmcli -f connection,vpn,ipv4,ipv6 connection show "$VPN_NAME" || true
      if command -v resolvectl >/dev/null; then resolvectl status || true; fi
      if command -v journalctl >/dev/null; then
        journalctl -b -u NetworkManager --since '-15 minutes' --no-pager || true
      else
        echo 'journalctl indisponível; consulte os logs do serviço neste sistema.'
      fi
      echo 'Logs adicionais: sudo journalctl -b _COMM=charon-nm --since "-15 minutes"'
      echo 'Revise os logs antes de compartilhar: podem conter login e endereços.'
      exit ;;
    -h|--help) usage; exit ;;
    *) usage >&2; exit 2 ;;
  esac
done
if [[ -z $login ]]; then
  read -r -p 'Login do CIn (iniciais, sem e-mail): ' login
fi
# Impede separadores interpretados por vpn.data e e-mail acidental.
[[ $login =~ ^[a-zA-Z0-9._-]+$ ]] || { echo 'Login inválido: use as iniciais, sem e-mail ou espaços.' >&2; exit 2; }
# shellcheck source=/dev/null
. /etc/os-release
# Eleva somente os comandos administrativos. Quando executado como root,
# a expansão do array vazio permite executar esses mesmos comandos sem sudo.
sudo_cmd=()
if ((EUID != 0)); then
  command -v sudo >/dev/null || { echo 'sudo é necessário.' >&2; exit 1; }
  sudo_cmd=(sudo)
fi
missing=()
# Verifica antes de instalar pacotes: atualizações podem recarregar serviços.
# Repete a verificação depois da instalação, antes de alterar o perfil.
check_active_vpns() {
  local active_types
  active_types=$(nmcli -t -f TYPE connection show --active)
  if [[ $'\n'"$active_types"$'\n' == *$'\nvpn\n'* ]]; then
    echo 'Desconecte as VPNs ativas e execute novamente para aplicar a configuração.' >&2
    exit 1
  fi
}
if command -v nmcli >/dev/null && nmcli general status >/dev/null 2>&1; then
  check_active_vpns
fi
# Usa nomes de pacotes da família detectada, sem alterar o ID real do sistema.
# Somente ID=fedora recebe os ajustes de certificado e GMP mais abaixo.
distro=${ID:-}
case "$distro" in
  fedora|debian|ubuntu|linuxmint|pop) ;;
  *)
    # Derivadas podem ter ID próprio e declarar sua base em ID_LIKE.
    case " ${ID_LIKE:-} " in
      *' debian '*|*' ubuntu '*) distro=debian ;;
    esac ;;
esac
case "$distro" in
  fedora)
    # O diálogo/editor GTK pode ser usado também fora do GNOME.
    packages=(NetworkManager NetworkManager-strongswan strongswan-charon-nm NetworkManager-strongswan-gnome ca-certificates p11-kit-trust openssl policycoreutils procps-ng)
    # No KDE, o editor e o diálogo de senha precisam do plugin do Plasma.
    if rpm -q plasma-nm >/dev/null 2>&1; then
      packages+=(plasma-nm-strongswan)
    fi
    for package in "${packages[@]}"; do
      rpm -q "$package" >/dev/null 2>&1 || missing+=("$package")
    done
    if ((${#missing[@]})); then "${sudo_cmd[@]}" dnf install -y "${missing[@]}"; fi ;;
  debian|ubuntu|linuxmint|pop)
    # O original instalava apenas network-manager-strongswan e
    # libcharon-extra-plugins; agora o gerenciador e os plugins cripto são
    # declarados explicitamente. strongswan-nm vem como dependência do plugin NM.
    packages=(network-manager network-manager-strongswan libstrongswan-extra-plugins libcharon-extra-plugins ca-certificates)
    # No Debian 13, EAP-MSCHAPv2 foi separado de libcharon-extra-plugins.
    # Em versões anteriores, o plugin já vem no pacote acima.
    # Atualiza os índices em toda configuração Debian para detectar o pacote
    # conforme os repositórios locais, mesmo se os demais já estiverem instalados.
    "${sudo_cmd[@]}" apt-get update
    # Um pacote conhecido pelo cache pode não ter versão instalável.
    candidate=$(LC_ALL=C apt-cache policy libcharon-extauth-plugins | awk '/Candidate:/ {print $2}')
    if [[ -n $candidate && $candidate != '(none)' ]]; then
      packages+=(libcharon-extauth-plugins)
    fi
    for package in "${packages[@]}"; do
      state=$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)
      [[ $state == 'install ok installed' ]] || missing+=("$package")
    done
    if ((${#missing[@]})); then
      "${sudo_cmd[@]}" apt-get install -y "${missing[@]}"
    fi ;;
  *) echo "Distribuição não suportada: ${ID:-desconhecida}." >&2; exit 1 ;;
esac
command -v nmcli >/dev/null
# Instalar o pacote não garante que o serviço esteja em execução. Não inicia
# nem reinicia NetworkManager automaticamente, para preservar a rede atual.
if ! nmcli general status >/dev/null; then
  echo 'Não foi possível acessar o NetworkManager. Verifique se o serviço está ativo.' >&2
  exit 1
fi
check_active_vpns
# Usa UUID para não modificar perfis de nome duplicado por engano.
profiles=$(nmcli -t -f UUID,NAME connection show)
uuids=()
while IFS=: read -r uuid name; do
  [[ $name != "$VPN_NAME" ]] || uuids+=("$uuid")
done <<< "$profiles"
((${#uuids[@]} <= 1)) || { echo 'Há perfis VPN-CIn duplicados. Renomeie-os antes de continuar.' >&2; exit 1; }
if ((${#uuids[@]})); then
  service=$(nmcli -g vpn.service-type connection show uuid "${uuids[0]}")
  [[ $service == org.freedesktop.NetworkManager.strongswan ]] || {
    echo 'VPN-CIn existente não é strongSwan. Renomeie esse perfil antes de continuar.' >&2; exit 1;
  }
fi

if [[ $ID == fedora ]]; then
  # Bloco novo e específico do Fedora; Debian utiliza a confiança disponível
  # no seu backend, sem receber estes arquivos ou esta prioridade GMP.
  temp_dir=$(mktemp -d)
  # Extrai somente a CA já confiável no Fedora: não baixa certificados do gateway.
  trust extract \
    --filter='pkcs11:id=%03%5C%AB%73%81%87%A8%CC%B0%A6%D5%94%E2%36%96%49%FF%05%99%2C;type=cert' \
    --format=pem-bundle "$temp_dir/ca.pem"
  fingerprint=$(openssl x509 -in "$temp_dir/ca.pem" -noout -fingerprint -sha256)
  [[ ${fingerprint#*=} == '4F:A3:12:6D:8D:3A:11:D1:C4:85:5A:4F:80:7C:BA:D6:CF:91:9D:3A:5A:88:B0:3B:EA:2C:63:72:D9:3C:40:C9' ]] || {
    echo 'CA GlobalSign Root R46 ausente ou diferente da esperada. Configuração interrompida.' >&2
    exit 1
  }
  openssl x509 -in "$temp_dir/ca.pem" -noout -checkend 0
  # Usa um caminho de sistema legível pelo daemon; um PEM em Downloads pode
  # ser bloqueado pelas permissões do diretório ou pelo SELinux.
  ca_path=/etc/pki/tls/certs/vpn-cin-globalsign-r46.pem
  "${sudo_cmd[@]}" install -m 0644 -o root -g root "$temp_dir/ca.pem" "$ca_path"
  "${sudo_cmd[@]}" restorecon "$ca_path"

  # Afeta as VPNs strongSwan do NetworkManager. Preserva a política global
  # DEFAULT do Fedora e a validação de cadeia, identidade e revogação.
  cat > "$temp_dir/compat.conf" <<'COMPAT'
# VPN CIn: compatibilidade com assinaturas RSA IKEv2 antigas.
charon-nm {
    plugins {
        gmp {
            load = 2
        }
    }
}
COMPAT
  compat_path=/etc/strongswan/strongswan.d/vpn-cin-compat.conf
  # Guarda a primeira versão de um arquivo preexistente diferente.
  if [[ -f $compat_path ]] && ! cmp -s "$temp_dir/compat.conf" "$compat_path"; then
    if [[ ! -e ${compat_path}.antes-vpn-cin ]]; then
      "${sudo_cmd[@]}" cp -p -- "$compat_path" "${compat_path}.antes-vpn-cin"
    fi
  fi
  "${sudo_cmd[@]}" install -m 0644 -o root -g root "$temp_dir/compat.conf" "$compat_path"
  "${sudo_cmd[@]}" restorecon "$compat_path"
fi
# Mantém do original: servidor, EAP, IP virtual, propostas IKE/ESP,
# DNS/domínios e IPv6 desabilitado somente neste perfil.
# password-flags mudou de 1 (segredo sob responsabilidade de um agente) para
# 2 (não salvar/pedir ao conectar). Isso não apaga senhas já guardadas em
# chaveiros externos. A interface gráfica pode oferecer outra política ao editar.
# proposal=yes usa as propostas explícitas; virtual=yes solicita IP ao gateway;
# ipcomp=no desabilita compressão IP. Autoconexão permanece desativada.
settings=(
  connection.autoconnect no
  vpn.data "user=${login},address=vpn.cin.ufpe.br,method=eap,encap=${encap},ipcomp=no,proposal=yes,password-flags=2,virtual=yes,esp=aes256-sha256-modp2048,ike=aes256-sha256-modp2048"
  ipv4.method auto
  ipv4.dns-search 'cin.ufpe.br,windows.cin.ufpe.br'
  ipv4.dns '172.21.2.151,172.21.2.152,172.21.2.153'
  ipv6.method disabled
  # Limpa também a interface fixa herdada de perfis criados pelo original.
  connection.interface-name ''
)
if [[ -n $ca_path ]]; then
  # Array de pares propriedade/valor: índice 2 é vpn.data e 3 é seu conteúdo.
  settings[3]+=",certificate=${ca_path}"
fi
if ((${#uuids[@]})); then
  service=$(nmcli -g vpn.service-type connection show uuid "${uuids[0]}")
  [[ $service == org.freedesktop.NetworkManager.strongswan ]] || {
    echo 'VPN-CIn existente não é strongSwan. Renomeie esse perfil antes de continuar.' >&2; exit 1;
  }
  # Atualiza sem apagar o perfil, preservando UUID e propriedades adicionais.
  # +vpn.data mescla as chaves: substitui as configuradas acima e preserva
  # chaves adicionais, inclusive uma CA escolhida pelo usuário no Debian.
  settings[2]=+vpn.data
  "${sudo_cmd[@]}" nmcli connection modify uuid "${uuids[0]}" "${settings[@]}"
else
  # O original usava ifname cin-ipsec-ike2. A VPN não depende dessa interface
  # física fictícia: '*' permite usar a conexão de base selecionada pelo NM.
  "${sudo_cmd[@]}" nmcli connection add type vpn vpn-type strongswan \
    con-name "$VPN_NAME" ifname '*' "${settings[@]}"
fi
if [[ $ID == fedora ]] && pgrep -x charon-nm >/dev/null; then
  # Sem VPNs ativas, encerra somente o backend; D-Bus o reabre na conexão.
  "${sudo_cmd[@]}" pkill -TERM -x charon-nm
fi
cat <<'HELP'

Perfil VPN-CIn configurado. A conexão ainda não foi testada.
Para conectar, selecione VPN-CIn no menu de rede do desktop.
Para autenticar pelo terminal, use o auxiliar opcional (sem sudo):
  bash conectar_vpn.sh
Para desconectar:
  nmcli connection down id VPN-CIn
Se falhar, execute logo após a tentativa:
  bash vpn_cin.sh --diagnostico
Se os pacotes acabaram de ser instalados e o serviço VPN não for encontrado,
reinicie o computador em um momento conveniente e tente novamente.
HELP
