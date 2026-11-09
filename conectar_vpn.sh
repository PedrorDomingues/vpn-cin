#!/usr/bin/env bash
# AVISO: este auxiliar e toda a parte de autenticação/verificação pelo terminal
# foram produzidos 100% com uso de inteligência artificial (IA).
# Revise o código antes de executar. O uso é por conta e risco de quem usar.
# Testes pontuais não garantem segurança ou funcionamento em outros ambientes.
# Autenticação EAP pelo terminal para Fedora, Debian e Ubuntu.
# Execute vpn_cin.sh antes para instalar dependências e configurar o perfil.
# Este auxiliar não altera o plugin instalado nem a autenticação do desktop:
# NM_VPN_PLUGIN_DIR fornece ao processo nmcli uma cópia temporária do plugin,
# com um adaptador external-ui sem GTK. A limpeza ocorre na saída normal e
# nos sinais tratados; SIGKILL ou queda de energia podem deixar temporários.
set -Eeuo pipefail
set +x  # Impede exibir a senha caso este script seja iniciado com bash -x.
if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  echo 'Uso: bash conectar_vpn.sh [PERFIL] (padrão: VPN-CIn)'
  exit 0
fi
(($# <= 1)) || { echo 'Uso: bash conectar_vpn.sh [PERFIL]' >&2; exit 2; }
profile=${1:-VPN-CIn}
echo 'Auxiliar de terminal produzido 100% com IA. Uso por sua conta e risco.' >&2
command -v nmcli >/dev/null || { echo 'Execute vpn_cin.sh para instalar as dependências.' >&2; exit 1; }
uuid=$(nmcli -g connection.uuid connection show id "$profile")
[[ $uuid =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]] || {
  echo 'Perfil ausente ou ambíguo. Use um nome de perfil único.' >&2; exit 1;
}
service=$(nmcli -g vpn.service-type connection show uuid "$uuid")
[[ $service == org.freedesktop.NetworkManager.strongswan ]] || {
  echo 'O perfil precisa usar strongSwan.' >&2; exit 1;
}
data=$(LC_ALL=C nmcli -g vpn.data connection show uuid "$uuid")
[[ $data =~ (^|,[[:space:]]*)method[[:space:]]*=[[:space:]]*eap(,|$) &&
   $data =~ (^|,[[:space:]]*)password-flags[[:space:]]*=[[:space:]]*2(,|$) ]] || {
  echo 'Use um perfil EAP com password-flags=2, como o criado por vpn_cin.sh.' >&2; exit 1;
}
# Copia somente os metadados públicos do plugin da distribuição.
plugin=''
for candidate in /usr/lib/NetworkManager/VPN/*strongswan*.name \
                 /usr/lib64/NetworkManager/VPN/*strongswan*.name \
                 /etc/NetworkManager/VPN/*strongswan*.name; do
  if [[ -f $candidate ]]; then plugin=$candidate; break; fi
done
[[ -n $plugin ]] || { echo 'Metadados do plugin strongSwan não encontrados.' >&2; exit 1; }
umask 077
temp_dir=$(mktemp -d "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/vpn-cin.XXXXXX")
trap 'rm -rf -- "$temp_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$temp_dir/plugins"
# O nmcli chama este adaptador para descobrir o campo de senha. O adaptador
# apenas descreve o campo; descarta a entrada de protocolo recebida do nmcli.
cat > "$temp_dir/auth-terminal" <<'AUTH'
#!/bin/sh
cat >/dev/null
cat <<'UI'
[VPN Plugin UI]
Version=2
Title=VPN CIn
Description=Informe a senha da VPN CIn

[password]
Label=Senha da VPN
IsSecret=true
ShouldAsk=true
UI
AUTH
chmod 700 "$temp_dir/auth-terminal"
# Detecta runtime com noexec antes de solicitar a senha.
if ! "$temp_dir/auth-terminal" </dev/null >/dev/null; then
  echo 'O diretório temporário não permite executar o adaptador de terminal.' >&2
  exit 1
fi
# Reconstrói somente as duas chaves GNOME. ENVIRON evita interpretar '&',
# barras ou escapes em caminhos temporários como código de substituição sed.
VPN_CIN_AUTH_PATH="$temp_dir/auth-terminal" awk '
  /^\[GNOME\][[:space:]]*$/ {
    gnome=1; seen=1; print;
    print "auth-dialog=" ENVIRON["VPN_CIN_AUTH_PATH"];
    print "supports-external-ui-mode=true"; next
  }
  /^\[/ {gnome=0}
  gnome && /^[[:space:]]*(auth-dialog|supports-external-ui-mode)[[:space:]]*=/ {next}
  {print}
  END {if (!seen) exit 1}
' "$plugin" > "$temp_dir/plugins/nm-strongswan-service.name"
read -r -s -p 'Senha da VPN CIn: ' vpn_password
printf '\n'
[[ -n $vpn_password ]] || { echo 'Senha vazia.' >&2; exit 1; }
# O campo é vpn.secrets.password, não vpn.password. A senha fica somente no
# arquivo temporário (0600), nunca em argumentos de processos ou no perfil.
printf 'vpn.secrets.password:%s\n' "$vpn_password" > "$temp_dir/secrets"
unset vpn_password
NM_VPN_PLUGIN_DIR="$temp_dir/plugins" nmcli connection up uuid "$uuid" passwd-file "$temp_dir/secrets"
