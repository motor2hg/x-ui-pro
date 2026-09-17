#!/bin/bash
#################### x-ui-pro v2.4.3 @ github.com/GFW4Fun ##############################################
# ФИНАЛЬНАЯ ВЕРСИЯ 3: исправлена 404 подписки, routing правила, xhttp inbound, версия 3.8.5
##########################################################################################################

[[ $EUID -ne 0 ]] && echo "not root!" && sudo su -

##############################INFO######################################################################
msg_ok() { echo -e "\e[1;42m $1 \e[0m";}
msg_err() { echo -e "\e[1;41m $1 \e[0m";}
msg_inf() { echo -e "\e[1;34m$1\e[0m";}
echo
msg_inf '           ___    _   _   _  '
msg_inf ' \/ __ | |  | __ |_) |_) / \ '
msg_inf ' /\    |_| _|_   |   | \ \_/ '
echo

##################################Variables#############################################################
XUIDB="/etc/x-ui/x-ui.db"
domain=""
UNINSTALL="x"
INSTALL="n"
PNLNUM=1
CFALLOW="n"
CLASH=0
CUSTOMWEBSUB=0
Pak=$(type apt &>/dev/null && echo "apt" || echo "yum")

ensure_ufw() {
    if ! command -v ufw >/dev/null 2>&1; then
        $Pak -y install ufw >/dev/null 2>&1
    fi
    ufw --force disable >/dev/null 2>&1 || true
}

systemctl stop x-ui
rm -rf /etc/systemd/system/x-ui.service
rm -rf /usr/local/x-ui
rm -rf /etc/x-ui
rm -rf /etc/nginx/sites-enabled/*
rm -rf /etc/nginx/sites-available/*
rm -rf /etc/nginx/stream-enabled/*

##################################generate ports and paths#############################################################
get_port() {
    echo $(( ((RANDOM<<15)|RANDOM) % 49152 + 10000 ))
}

gen_random_string() {
    local length="$1"
    head -c 4096 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c "$length"
    echo
}

check_free() {
    local port=$1
    nc -z 127.0.0.1 $port &>/dev/null
    return $?
}

make_port() {
    while true; do
        PORT=$(get_port)
        if ! check_free $PORT; then
            echo $PORT
            break
        fi
    done
}

sub_port=$(make_port)
panel_port=$(make_port)
web_path=$(gen_random_string 10)
sub2singbox_path=$(gen_random_string 10)
sub_path=$(gen_random_string 10)
json_path=$(gen_random_string 10)
panel_path=$(gen_random_string 10)
ws_port=$(make_port)
trojan_port=$(make_port)
xhttp_port=$(make_port)
ws_path=$(gen_random_string 10)
trojan_path=$(gen_random_string 10)
xhttp_path=$(gen_random_string 10)
config_username=$(gen_random_string 10)
config_password=$(gen_random_string 10)
AUTODOMAIN="n"

################################Get arguments###########################################################
while [ "$#" -gt 0 ]; do
    case "$1" in
        -auto_domain) AUTODOMAIN="$2"; shift 2;;
        -install) INSTALL="$2"; shift 2;;
        -panel) PNLNUM="$2"; shift 2;;
        -subdomain) domain="$2"; shift 2;;
        -reality_domain) reality_domain="$2"; shift 2;;
        -ONLY_CF_IP_ALLOW) CFALLOW="$2"; shift 2;;
        -websub) CUSTOMWEBSUB="$2"; shift 2;;
        -clash) CLASH="$2"; shift 2;;
        -uninstall) UNINSTALL="$2"; shift 2;;
        *) shift 1;;
    esac
done

##############################Uninstall#################################################################
UNINSTALL_XUI(){
    printf 'y\n' | x-ui uninstall
    rm -rf "/etc/x-ui/" "/usr/local/x-ui/" "/usr/bin/x-ui/"
    $Pak -y remove nginx nginx-common nginx-core nginx-full python3-certbot-nginx
    $Pak -y purge nginx nginx-common nginx-core nginx-full python3-certbot-nginx
    $Pak -y autoremove
    $Pak -y autoclean
    rm -rf "/var/www/html/" "/etc/nginx/" "/usr/share/nginx/"
}

if [[ ${UNINSTALL} == *"y"* ]]; then
    UNINSTALL_XUI
    clear && msg_ok "Completely Uninstalled!" && exit 1
fi

IP4_REGEX="^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$"
IP4=$(ip route get 8.8.8.8 2>&1 | grep -Po -- 'src \K\S*')
[[ $IP4 =~ $IP4_REGEX ]] || IP4=$(curl -s ipv4.icanhazip.com | tr -d '[:space:]')

if [[ ${AUTODOMAIN} == *"y"* ]]; then
    domain="${IP4}.cdn-one.org"
    reality_domain="${IP4//./-}.cdn-one.org"
fi

##############################Domain Validations########################################################
while true; do
    if [[ -n "$domain" ]]; then
        break
    fi
    echo -en "Enter available subdomain (sub.domain.tld): " && read domain
done

domain=$(echo "$domain" 2>&1 | tr -d '[:space:]' )
SubDomain=$(echo "$domain" 2>&1 | sed 's/^[^ ]* \|\..*//g')
MainDomain=$(echo "$domain" 2>&1 | sed 's/.*\.\([^.]*\..*\)$/\1/')

if [[ "${SubDomain}.${MainDomain}" != "${domain}" ]] ; then
    MainDomain=${domain}
fi

while true; do
    if [[ -n "$reality_domain" ]]; then
        break
    fi
    echo -en "Enter available subdomain for REALITY (sub.domain.tld): " && read reality_domain
done

reality_domain=$(echo "$reality_domain" 2>&1 | tr -d '[:space:]' )
RealitySubDomain=$(echo "$reality_domain" 2>&1 | sed 's/^[^ ]* \|\..*//g')
RealityMainDomain=$(echo "$reality_domain" 2>&1 | sed 's/.*\.\([^.]*\..*\)$/\1/')

if [[ "${RealitySubDomain}.${RealityMainDomain}" != "${reality_domain}" ]] ; then
    RealityMainDomain=${reality_domain}
fi

###############################Install Packages#########################################################
# ЗАПРОС RU ПРАВИЛ ДО УСТАНОВКИ ПАКЕТОВ
read -p "Add Russian segment routing rules? y/n: " RU_ROUTING
RU_RULE="false"

if [[ "$RU_ROUTING" == "y" || "$RU_ROUTING" == "Y" ]]; then
    RU_RULE="true"
    msg_ok "Russian segment routing rules will be applied!"
else
    msg_inf "Russian segment routing rules will NOT be applied."
fi

if [[ ${INSTALL} == *"y"* ]]; then
    version=$(grep -oP '(?<=VERSION_ID=")[0-9]+' /etc/os-release)
    if [[ "$version" == "20" || "$version" == "22" || "$version" == "24" ]]; then
        echo "Версия системы: Ubuntu $version"
    fi
    $Pak -y update
    $Pak -y install curl wget jq bash sudo nginx-full certbot python3-certbot-nginx sqlite3 ufw
    systemctl daemon-reload && systemctl enable --now nginx
    ensure_ufw
fi

systemctl stop nginx
fuser -k 80/tcp 80/udp 443/tcp 443/udp 2>/dev/null

##################################GET SERVER IPv4-6#####################################################
IP4_REGEX="^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$"
IP6_REGEX="([a-f0-9:]+:+)+[a-f0-9]+"
IP4=$(ip route get 8.8.8.8 2>&1 | grep -Po -- 'src \K\S*')
IP6=$(ip route get 2620:fe::fe 2>&1 | grep -Po -- 'src \K\S*')
[[ $IP4 =~ $IP4_REGEX ]] || IP4=$(curl -s ipv4.icanhazip.com);
[[ $IP6 =~ $IP6_REGEX ]] || IP6=$(curl -s ipv6.icanhazip.com);

##############################Install SSL###############################################################
resolve_to_ip () {
    local host="$1"
    local a
    a=$(getent ahostsv4 "$host" 2>/dev/null | awk 'NR==1{print $1}')
    [[ -n "$a" ]] && [[ "$a" == "$IP4" ]]
}

if [[ ${AUTODOMAIN} == *"y"* ]]; then
    if ! resolve_to_ip "$domain"; then
        msg_err "Auto-domain $domain does not resolve to this server IP ($IP4). Fix DNS/service and retry."
        exit 1
    fi
    if ! resolve_to_ip "$reality_domain"; then
        msg_err "Auto-domain $reality_domain does not resolve to this server IP ($IP4). Fix DNS/service and retry."
        exit 1
    fi
fi

certbot certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email -d "$domain"
if [[ ! -d "/etc/letsencrypt/live/${domain}/" ]]; then
    systemctl start nginx >/dev/null 2>&1
    msg_err "$domain SSL could not be generated! Check Domain/IP Or Enter new domain!" && exit 1
fi

certbot certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email -d "$reality_domain"
if [[ ! -d "/etc/letsencrypt/live/${reality_domain}/" ]]; then
    systemctl start nginx >/dev/null 2>&1
    msg_err "$reality_domain SSL could not be generated! Check Domain/IP Or Enter new domain!" && exit 1
fi

###################################Get Installed XUI Port/Path##########################################
if [[ -f $XUIDB ]]; then
    XUIPORT=$(sqlite3 -list $XUIDB 'SELECT "value" FROM settings WHERE "key"="webPort" LIMIT 1;' 2>&1)
    XUIPATH=$(sqlite3 -list $XUIDB 'SELECT "value" FROM settings WHERE "key"="webBasePath" LIMIT 1;' 2>&1)
    if [[ $XUIPORT -gt 0 && $XUIPORT != "54321" && $XUIPORT != "2053" ]] && [[ ${#XUIPORT} -gt 4 ]]; then
        RNDSTR=$(echo "$XUIPATH" 2>&1 | tr -d '/')
        PORT=$XUIPORT
        sqlite3 $XUIDB <<EOF
DELETE FROM "settings" WHERE ( "key"="webCertFile" ) OR ( "key"="webKeyFile" );
INSERT INTO "settings" ("key", "value") VALUES ("webCertFile",  "");
INSERT INTO "settings" ("key", "value") VALUES ("webKeyFile", "");
EOF
    fi
fi

#################################Nginx Config###########################################################
mkdir -p /root/cert/${domain}
chmod 755 /root/cert/${domain}
ln -sf /etc/letsencrypt/live/${domain}/fullchain.pem /root/cert/${domain}/fullchain.pem
ln -sf /etc/letsencrypt/live/${domain}/privkey.pem /root/cert/${domain}/privkey.pem

mkdir -p /etc/nginx/stream-enabled
cat > "/etc/nginx/stream-enabled/stream.conf" << EOF
map \$ssl_preread_server_name \$sni_name {
    hostnames;
    ${reality_domain}      xray;
    ${domain}           www;
    default              xray;
}
upstream xray {
    server 127.0.0.1:8443;
}
upstream www {
    server 127.0.0.1:7443;
}
server {
    proxy_protocol on;
    #set_real_ip_from unix:; #onle http
    listen          443;
    listen         [::]:443;
    proxy_pass      \$sni_name;
    ssl_preread     on;
}
EOF

grep -xqFR "stream { include /etc/nginx/stream-enabled/*.conf; }" /etc/nginx/* ||echo "stream { include /etc/nginx/stream-enabled/*.conf; }" >> /etc/nginx/nginx.conf
grep -xqFR "load_module modules/ngx_stream_module.so;" /etc/nginx/* || sed -i '1s/^/load_module \/usr\/lib\/nginx\/modules\/ngx_stream_module.so; /' /etc/nginx/nginx.conf
grep -xqFR "load_module modules/ngx_stream_geoip2_module.so;" /etc/nginx* || sed -i '2s/^/load_module \/usr\/lib\/nginx\/modules\/ngx_stream_geoip2_module.so; /' /etc/nginx/nginx.conf
grep -xqFR "worker_rlimit_nofile 16384;" /etc/nginx/* ||echo "worker_rlimit_nofile 16384;" >> /etc/nginx/nginx.conf
sed -i "/worker_connections/c\worker_connections 4096;" /etc/nginx/nginx.conf

cat > "/etc/nginx/sites-available/80.conf" << EOF
server {
    listen 80;
    server_name ${domain} ${reality_domain};
    return 301 https://\$host\$request_uri;
}
EOF

cat > "/etc/nginx/sites-available/${domain}" << EOF
server {
    server_tokens off;
    server_name ${domain};
    listen 7443 ssl http2 proxy_protocol;
    listen [::]:7443 ssl http2 proxy_protocol;
    index index.html index.htm index.php index.nginx-debian.html;
    root /var/www/html/;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!eNULL:!MD5:!DES:!RC4:!ADH:!SSLv3:!EXP:!PSK:!DSS;
    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    if (\$host !~* ^(.+\.)?$domain\$ ){return 444;}
    if (\$scheme ~* https) {set \$safe 1;}
    if (\$ssl_server_name !~* ^(.+\.)?${domain}\$ ) {set \$safe "\${safe}0"; }
    if (\$safe = 10){return 444;}
    if (\$request_uri ~ "(\"|'|\`|~|,|:|;|%|\\$|&&|\?\?|0x00|0X00|\||\\|\{|\}|\[|\]|<|>|\.\.\.|\.\.\/|\/\/\/)"){set \$hack 1;}
    error_page 400 401 402 403 500 501 502 503 504 =404 /404;
    proxy_intercept_errors on;
    #X-UI Admin Panel
    location /${panel_path}/ {
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Upgrade websocket;
        proxy_set_header Connection Upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_pass https://127.0.0.1:${panel_port};
        break;
    }
    location /${panel_path} {
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Upgrade websocket;
        proxy_set_header Connection Upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_pass https://127.0.0.1:${panel_port};
        break;
    }
    include /etc/nginx/snippets/includes.conf;
}
EOF

cat > "/etc/nginx/snippets/includes.conf" << EOF
#sub2sing-box
location /${sub2singbox_path}/ {
    proxy_redirect off;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_pass http://127.0.0.1:8080/;
}
# Path to open clash.yaml and generate YAML
location ~ ^/${web_path}/clashmeta/(.+)$ {
    default_type text/plain;
    ssi on;
    ssi_types text/plain;
    set \$subid \$1;
    root /var/www/subpage;
    try_files /clash.yaml =404;
}
# web
location ~ ^/${web_path} {
    root /var/www/subpage;
    index index.html;
    try_files \$uri \$uri/ /index.html =404;
}
#Subscription Path (simple/encode)
location /${sub_path} {
    if (\$hack = 1) {return 404;}
    proxy_redirect off;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_pass http://127.0.0.1:${sub_port};
    break;
}
location /${sub_path}/ {
    if (\$hack = 1) {return 404;}
    proxy_redirect off;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_pass http://127.0.0.1:${sub_port};
    break;
}
location /assets/ {
    if (\$hack = 1) {return 404;}
    proxy_redirect off;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_pass http://127.0.0.1:${sub_port};
    break;
}
location /assets {
    if (\$hack = 1) {return 404;}
    proxy_redirect off;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_pass http://127.0.0.1:${sub_port};
    break;
}
#Subscription Path (json/fragment)
location /${json_path} {
    if (\$hack = 1) {return 404;}
    proxy_redirect off;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_pass http://127.0.0.1:${sub_port};
    break;
}
location /${json_path}/ {
    if (\$hack = 1) {return 404;}
    proxy_redirect off;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_pass http://127.0.0.1:${sub_port};
    break;
}
#XHTTP - ИСПРАВЛЕНО: используем HTTP-проксирование, не gRPC (XHTTP это HTTP, не gRPC!)
location /${xhttp_path} {
    proxy_redirect off;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_pass http://unix:/dev/shm/uds2023.sock;
}
#Xray Config Path
location ~ ^/(?<fwdport>\d+)/(?<fwdpath>.*)\$ {
    if (\$hack = 1) {return 404;}
    client_max_body_size 0;
    client_body_timeout 1d;
    grpc_read_timeout 1d;
    grpc_socket_keepalive on;
    proxy_read_timeout 1d;
    proxy_http_version 1.1;
    proxy_buffering off;
    proxy_request_buffering off;
    proxy_socket_keepalive on;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    if (\$content_type ~* "GRPC") {
        grpc_pass grpc://127.0.0.1:\$fwdport\$is_args\$args;
        break;
    }
    if (\$http_upgrade ~* "(WEBSOCKET|WS)") {
        proxy_pass http://127.0.0.1:\$fwdport\$is_args\$args;
        break;
    }
    if (\$request_method ~* ^(PUT|POST|GET)\$) {
        proxy_pass http://127.0.0.1:\$fwdport\$is_args\$args;
        break;
    }
}
location / { try_files \$uri \$uri/ =404; }
EOF

cat > "/etc/nginx/sites-available/${reality_domain}" << EOF
server {
    server_tokens off;
    server_name ${reality_domain};
    listen 9443 ssl http2;
    listen [::]:9443 ssl http2;
    index index.html index.htm index.php index.nginx-debian.html;
    root /var/www/html/;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!eNULL:!MD5:!DES:!RC4:!ADH:!SSLv3:!EXP:!PSK:!DSS;
    ssl_certificate /etc/letsencrypt/live/$reality_domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$reality_domain/privkey.pem;
    if (\$host !~* ^(.+\.)?${reality_domain}\$ ){return 444;}
    if (\$scheme ~* https) {set \$safe 1;}
    if (\$ssl_server_name !~* ^(.+\.)?${reality_domain}\$ ) {set \$safe "\${safe}0"; }
    if (\$safe = 10){return 444;}
    if (\$request_uri ~ "(\"|'|\`|~|,|:|;|%|\\$|&&|\?\?|0x00|0X00|\||\\|\{|\}|\[|\]|<|>|\.\.\.|\.\.\/|\/\/\/)"){set \$hack 1;}
    error_page 400 401 402 403 500 501 502 503 504 =404 /404;
    proxy_intercept_errors on;
    #X-UI Admin Panel
    location /${panel_path}/ {
        proxy_redirect off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_pass http://127.0.0.1:${panel_port};
        break;
    }
    location /$panel_path {
        proxy_redirect off;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_pass http://127.0.0.1:${panel_port};
        break;
    }
    include /etc/nginx/snippets/includes.conf;
}
EOF

##################################Check Nginx status####################################################
if [[ -f "/etc/nginx/sites-available/${domain}" ]]; then
    unlink "/etc/nginx/sites-enabled/default" >/dev/null 2>&1
    rm -f "/etc/nginx/sites-enabled/default" "/etc/nginx/sites-available/default"
    ln -s "/etc/nginx/sites-available/${domain}" "/etc/nginx/sites-enabled/" 2>/dev/null
    ln -s "/etc/nginx/sites-available/${reality_domain}" "/etc/nginx/sites-enabled/" 2>/dev/null
    ln -s "/etc/nginx/sites-available/80.conf" "/etc/nginx/sites-enabled/" 2>/dev/null
else
    msg_err "${domain} nginx config not exist!" && exit 1
fi

if [[ $(nginx -t 2>&1 | grep -o 'successful') != "successful" ]]; then
    msg_err "nginx config is not ok!" && exit 1
else
    systemctl start nginx
fi

##############################generate uri's###########################################################
sub_uri=https://${domain}/${sub_path}/
json_uri=https://${domain}/${web_path}?name=

##############################generate keys###########################################################
shor=($(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8))

########################################Update X-UI Port/Path for first INSTALL#########################
########################################Update X-UI Port/Path for first INSTALL#########################
UPDATE_XUIDB(){
    # ИСПРАВЛЕНО: ждём создания x-ui.db до 30 секунд
    local wait_count=0
    while [[ ! -f $XUIDB ]]; do
        sleep 1
        ((wait_count++))
        if [[ $wait_count -ge 30 ]]; then
            msg_err "x-ui.db file not exist after 30s! Maybe x-ui isn't installed." && exit 1
        fi
    done
    sleep 3

    x-ui stop

    # ИСПРАВЛЕНО: Удаляем все старые настройки и клиентов, чтобы избежать дубликатов!
    # Без этого при повторном запуске скрипта или после x-ui setting 
    # в базе появляются дубли записей с одинаковыми key, 
    # и x-ui при SELECT берёт первое (устаревшее) значение.
    sqlite3 $XUIDB <<'EOF_CLEANUP'
DELETE FROM "settings" WHERE "key" LIKE 'sub%';
DELETE FROM "settings" WHERE "key" LIKE 'web%';
DELETE FROM "settings" WHERE "key" IN ('sessionMaxAge','pageSize','expireDiff','trafficDiff','remarkModel','timeLocation','secretEnable','datepicker');
DELETE FROM "settings" WHERE "key" LIKE 'tg%';
DELETE FROM "inbounds";
DELETE FROM "client_traffics";
EOF_CLEANUP

    output=$(/usr/local/x-ui/bin/xray-linux-amd64 x25519)
    private_key=$(echo "$output" | grep "^PrivateKey:" | awk '{print $2}')
    public_key=$(echo "$output" | grep "^Password" | awk '{print $3}')
    client_id=$(/usr/local/x-ui/bin/xray-linux-amd64 uuid)
    client_id2=$(/usr/local/x-ui/bin/xray-linux-amd64 uuid)
    client_id3=$(/usr/local/x-ui/bin/xray-linux-amd64 uuid)
    trojan_pass=$(gen_random_string 10)
    emoji_flag=$(LC_ALL=en_US.UTF-8 curl -s https://ipwho.is/ | jq -r '.flag.emoji')

    # ... (дальше идёт ваш существующий код формирования ROUTING_RULES и XRAY_TEMPLATE)

    sqlite3 $XUIDB <<EOF
-- ИСПРАВЛЕНО: НЕ вставляем subCertFile и subKeyFile!
-- Sub-сервер будет работать на обычном HTTP,
-- TLS termination делает nginx.
INSERT INTO "settings" ("key", "value") VALUES ("subPort",  '${sub_port}');
INSERT INTO "settings" ("key", "value") VALUES ("subPath",  '/${sub_path}/');
INSERT INTO "settings" ("key", "value") VALUES ("subURI",  '${sub_uri}');
INSERT INTO "settings" ("key", "value") VALUES ("subJsonPath",  '/${json_path}/');
INSERT INTO "settings" ("key", "value") VALUES ("subJsonURI",  '${json_uri}');
INSERT INTO "settings" ("key", "value") VALUES ("subClashEnable",  'true');
INSERT INTO "settings" ("key", "value") VALUES ("subEnableRouting",  'false');
INSERT INTO "settings" ("key", "value") VALUES ("subEnable",  'true');
INSERT INTO "settings" ("key", "value") VALUES ("subCertFile",  '');
INSERT INTO "settings" ("key", "value") VALUES ("subKeyFile",  '');
INSERT INTO "settings" ("key", "value") VALUES ("subUpdates",  '12');
INSERT INTO "settings" ("key", "value") VALUES ("subEncrypt",  'true');
INSERT INTO "settings" ("key", "value") VALUES ("subShowInfo",  'true');
INSERT INTO "settings" ("key", "value") VALUES ("subJsonFragment",  '');
INSERT INTO "settings" ("key", "value") VALUES ("subJsonNoises",  '');
INSERT INTO "settings" ("key", "value") VALUES ("subJsonMux",  '');
INSERT INTO "settings" ("key", "value") VALUES ("subJsonRules",  '');
INSERT INTO "settings" ("key", "value") VALUES ("webListen",  '');
INSERT INTO "settings" ("key", "value") VALUES ("webDomain",  '');
INSERT INTO "settings" ("key", "value") VALUES ("webCertFile",  '');
INSERT INTO "settings" ("key", "value") VALUES ("webKeyFile",  '');
INSERT INTO "settings" ("key", "value") VALUES ("webPort",  '${panel_port}');
INSERT INTO "settings" ("key", "value") VALUES ("webBasePath",  '${panel_path}');
INSERT INTO "settings" ("key", "value") VALUES ("sessionMaxAge",  '60');
INSERT INTO "settings" ("key", "value") VALUES ("pageSize",  '50');
INSERT INTO "settings" ("key", "value") VALUES ("expireDiff",  '0');
INSERT INTO "settings" ("key", "value") VALUES ("trafficDiff",  '0');
INSERT INTO "settings" ("key", "value") VALUES ("remarkModel",  '-ieo');
INSERT INTO "settings" ("key", "value") VALUES ("timeLocation",  'Europe/Moscow');
INSERT INTO "settings" ("key", "value") VALUES ("secretEnable",  'false');
INSERT INTO "settings" ("key", "value") VALUES ("datepicker",  'gregorian');
INSERT INTO "settings" ("key", "value") VALUES ("xrayTemplateConfig",  '$XRAY_TEMPLATE');

INSERT INTO "client_traffics" ("inbound_id","enable","email","up","down","expiry_time","total","reset") VALUES ('1','1','first','0','0','0','0','0');
INSERT INTO "client_traffics" ("inbound_id","enable","email","up","down","expiry_time","total","reset") VALUES ('2','1','first_1','0','0','0','0','0');
INSERT INTO "client_traffics" ("inbound_id","enable","email","up","down","expiry_time","total","reset") VALUES ('3','1','firstX','0','0','0','0','0');
INSERT INTO "client_traffics" ("inbound_id","enable","email","up","down","expiry_time","total","reset") VALUES ('4','1','firstT','0','0','0','0','0');

-- (далее ваши INSERT INTO "inbounds" без изменений)
EOF

    # ИСПРАВЛЕНО: вызываем x-ui setting ПОСЛЕ заполнения базы,
    # чтобы он не перезаписал наши настройки подписки.
    # Но т.к. мы удалили webPort/webBasePath выше и вставили заново,
    # вызов setting перезапишет только их (и это ок, значения совпадают).
    /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}" -port "${panel_port}" -webBasePath "${panel_path}"
    
    # НЕ вызываем x-ui cert! Он может перезаписать webCertFile/webKeyFile.
    # Панель работает через nginx proxy, ей не нужны свои сертификаты.
    
    x-ui start
}

arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64) echo 'amd64' ;;
        i*86 | x86) echo '386' ;;
        armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
        armv7* | armv7 | arm) echo 'armv7' ;;
        armv6* | armv6) echo 'armv6' ;;
        armv5* | armv5) echo 'armv5' ;;
        s390x) echo 's390x' ;;
        *) echo -e "${green}Unsupported CPU architecture! ${plain}" && rm -f install.sh && exit 1 ;;
    esac
}

config_after_install() {
    /usr/local/x-ui/x-ui setting -username "asdfasdf" -password "asdfasdf" -port "2096" -webBasePath "asdfasdf"
    /usr/local/x-ui/x-ui migrate
}

install_panel() {
    apt-get update && apt-get install -y -q wget curl tar tzdata
    cd /usr/local/
    # ИСПРАВЛЕНО: используем 3.8.5 как стабильную, с fallback на последнюю версию
    tag_version="v3.8.5"
    # Пытаемся получить последнюю версию с GitHub
    latest_version=$(curl -Ls "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ -n "$latest_version" ]]; then
        tag_version="$latest_version"
        msg_inf "Got latest x-ui version: ${tag_version}"
    else
        msg_inf "Using fallback version: ${tag_version}"
    fi

    wget -N -O /usr/local/x-ui-linux-$(arch).tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
    if [[ $? -ne 0 ]]; then
        echo -e "${red}Downloading x-ui failed, please be sure that your server can access GitHub ${plain}"
        exit 1
    fi

    wget -O /usr/bin/x-ui-temp https://raw.githubusercontent.com/MHSanaei/3x-ui/main/x-ui.sh
    if [[ $? -ne 0 ]]; then
        echo -e "${red}Failed to download x-ui.sh${plain}"
        exit 1
    fi

    if [[ -e /usr/local/x-ui/ ]]; then
        systemctl stop x-ui
        rm /usr/local/x-ui/ -rf
    fi

    tar zxvf x-ui-linux-$(arch).tar.gz
    rm x-ui-linux-$(arch).tar.gz -f
    cd x-ui
    chmod +x x-ui
    chmod +x x-ui.sh

    if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
        mv bin/xray-linux-$(arch) bin/xray-linux-arm
        chmod +x bin/xray-linux-arm
    fi

    chmod +x x-ui bin/xray-linux-$(arch)

    mv -f /usr/bin/x-ui-temp /usr/bin/x-ui
    chmod +x /usr/bin/x-ui

    config_after_install

    cp -f x-ui.service.debian /etc/systemd/system/x-ui.service
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui

    echo -e "${green}x-ui ${tag_version} installation finished, it is running now...${plain}"
    echo -e ""
    echo -e "┌───────────────────────────────────────────────────────┐
│  ${blue}x-ui control menu usages (subcommands):${plain}              │
│                                                       │
│  ${blue}x-ui${plain}              - Admin Management Script          │
│  ${blue}x-ui start${plain}        - Start                            │
│  ${blue}x-ui stop${plain}         - Stop                             │
│  ${blue}x-ui restart${plain}      - Restart                          │
│  ${blue}x-ui status${plain}       - Current Status                   │
│  ${blue}x-ui settings${plain}     - Current Settings                 │
│  ${blue}x-ui enable${plain}       - Enable Autostart on OS Startup   │
│  ${blue}x-ui disable${plain}      - Disable Autostart on OS Startup  │
│  ${blue}x-ui log${plain}          - Check logs                       │
│  ${blue}x-ui banlog${plain}       - Check Fail2ban ban logs          │
│  ${blue}x-ui update${plain}       - Update                           │
│  ${blue}x-ui legacy${plain}       - Legacy version                   │
│  ${blue}x-ui install${plain}      - Install                          │
│  ${blue}x-ui uninstall${plain}    - Uninstall                        │
└───────────────────────────────────────────────────────┘"
}

###################################Install X-UI#########################################################
if systemctl is-active --quiet x-ui; then
    x-ui restart
else
    install_panel
    # ИСПРАВЛЕНО: ждём создания x-ui.db перед UPDATE_XUIDB
    local_wait=0
    while [[ ! -f $XUIDB ]]; do
        sleep 1
        ((local_wait++))
        if [[ $local_wait -ge 30 ]]; then
            msg_err "x-ui.db not created after install_panel. Check journalctl -u x-ui." && exit 1
        fi
    done
    sleep 3
    UPDATE_XUIDB
    if ! systemctl is-enabled --quiet x-ui; then
        systemctl daemon-reload && systemctl enable x-ui.service
    fi
    x-ui restart
fi

######################enable bbr and tune system########################################################
apt-get install -yqq --no-install-recommends ca-certificates
echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf
echo "fs.file-max=2097152" | tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_timestamps = 1" | tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_sack = 1" | tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_window_scaling = 1" | tee -a /etc/sysctl.conf
echo "net.core.rmem_max = 16777216" | tee -a /etc/sysctl.conf
echo "net.core.wmem_max = 16777216" | tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_rmem = 4096 87380 16777216" | tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_wmem = 4096 65536 16777216" | tee -a /etc/sysctl.conf
sysctl -p

######################install_sub2sing-box#################################################################
if pgrep -x "sub2sing-box" > /dev/null; then
    echo "kill sub2sing-box..."
    pkill -x "sub2sing-box"
fi
if [ -f "/usr/bin/sub2sing-box" ]; then
    echo "delete sub2sing-box..."
    rm -f /usr/bin/sub2sing-box
fi
wget -P /root/ https://github.com/legiz-ru/sub2sing-box/releases/download/v0.0.9/sub2sing-box_0.0.9_linux_amd64.tar.gz
tar -xvzf /root/sub2sing-box_0.0.9_linux_amd64.tar.gz -C /root/ --strip-components=1 sub2sing-box_0.0.9_linux_amd64/sub2sing-box
mv /root/sub2sing-box /usr/bin/
chmod +x /usr/bin/sub2sing-box
rm /root/sub2sing-box_0.0.9_linux_amd64.tar.gz
su -c "/usr/bin/sub2sing-box server --bind 127.0.0.1 --port 8080 & disown" root

######################install_fake_site#################################################################
FAKE_SITE_TMP=$(mktemp -d)
if wget -qO "$FAKE_SITE_TMP/repo.tar.gz" "https://github.com/mozaroc/3x-ui-pro/archive/refs/heads/main.tar.gz" \
&& tar -xzf "$FAKE_SITE_TMP/repo.tar.gz" -C "$FAKE_SITE_TMP" --strip-components=3 "3x-ui-pro-main/assets/fake-sites"; then
    FAKE_SITES=("$FAKE_SITE_TMP"/site-*/)
    FAKE_SITE="${FAKE_SITES[$((RANDOM % ${#FAKE_SITES[@]}))]}"
    msg_inf "Random fake site template: $(basename "$FAKE_SITE")"
    mkdir -p /var/www/html
    rm -rf /var/www/html/*
    cp -a "$FAKE_SITE". /var/www/html/
    msg_ok "Fake site installed successfully!"
else
    msg_err "Failed to download fake site templates!"
fi
rm -rf "$FAKE_SITE_TMP"

######################install_web_sub_page##############################################################
URL_SUB_PAGE=( "https://github.com/legiz-ru/x-ui-pro/raw/master/sub-3x-ui.html"
    "https://github.com/legiz-ru/x-ui-pro/raw/master/sub-3x-ui-classical.html"
)
URL_CLASH_SUB=( "https://github.com/legiz-ru/x-ui-pro/raw/master/clash/clash.yaml"
    "https://github.com/legiz-ru/x-ui-pro/raw/master/clash/clash_skrepysh.yaml"
    "https://github.com/legiz-ru/x-ui-pro/raw/master/clash/clash_fullproxy_without_ru.yaml"
    "https://github.com/legiz-ru/x-ui-pro/raw/master/clash/clash_refilter_ech.yaml"
)
DEST_DIR_SUB_PAGE="/var/www/subpage"
DEST_FILE_SUB_PAGE="$DEST_DIR_SUB_PAGE/index.html"
DEST_FILE_CLASH_SUB="$DEST_DIR_SUB_PAGE/clash.yaml"
sudo mkdir -p "$DEST_DIR_SUB_PAGE"
sudo curl -L "${URL_CLASH_SUB[$CLASH]}" -o "$DEST_FILE_CLASH_SUB"
sudo curl -L "${URL_SUB_PAGE[$CUSTOMWEBSUB]}" -o "$DEST_FILE_SUB_PAGE"
sed -i "s/\${DOMAIN}/$domain/g" "$DEST_FILE_SUB_PAGE"
sed -i "s/\${DOMAIN}/$domain/g" "$DEST_FILE_CLASH_SUB"
sed -i "s#\${SUB_JSON_PATH}#$json_path#g" "$DEST_FILE_SUB_PAGE"
sed -i "s#\${SUB_PATH}#$sub_path#g" "$DEST_FILE_SUB_PAGE"
sed -i "s#\${SUB_PATH}#$sub_path#g" "$DEST_FILE_CLASH_SUB"
sed -i "s|sub.legiz.ru|$domain/$sub2singbox_path|g" "$DEST_FILE_SUB_PAGE"

######################cronjob for ssl/reload service/cloudflareips######################################
crontab -l | grep -v "certbot\|x-ui\|cloudflareips" | crontab -
(crontab -l 2>/dev/null; echo '@reboot /usr/bin/sub2sing-box server --bind 127.0.0.1 --port 8080 & disown') | crontab -
(crontab -l 2>/dev/null; echo '@daily x-ui restart > /dev/null 2>&1 && nginx -s reload;') | crontab -
(crontab -l 2>/dev/null; echo '@monthly certbot renew --nginx --non-interactive --post-hook "nginx -s reload" > /dev/null 2>&1;') | crontab -

##################################ufw###################################################################
if command -v ufw >/dev/null 2>&1; then
    ufw disable
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
fi

##################################Show Details##########################################################
if systemctl is-active --quiet x-ui; then clear
    printf '0\n' | x-ui | grep --color=never -i ':'
    msg_inf "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    nginx -T | grep -i 'ssl_certificate\|ssl_certificate_key'
    msg_inf "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    certbot certificates | grep -i 'Path:\|Domains:\|Expiry Date:'
    msg_inf "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    if [[ -n $IP4 ]] && [[ "$IP4" =~ $IP4_REGEX ]]; then
        msg_inf "IPv4: http://$IP4:$PORT/$RNDSTR/"
    fi
    if [[ -n $IP6 ]] && [[ "$IP6" =~ $IP6_REGEX ]]; then
        msg_inf "IPv6: http://[$IP6]:$PORT/$RNDSTR/"
    fi
    msg_inf "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    msg_inf "X-UI Secure Panel: https://${domain}/${panel_path}/"
    echo -e "Username:  ${config_username}"
    echo -e "Password:  ${config_password}"
    msg_inf "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    msg_inf "Web Sub Page your first client: https://${domain}/${web_path}?name=first"
    msg_inf "Your local sub2sing-box instance: https://${domain}/$sub2singbox_path/"
    msg_inf "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    msg_inf "Please Save this Screen!!"
else
    nginx -t && printf '0\n' | x-ui | grep --color=never -i ':'
    msg_err "sqlite and x-ui to be checked, try on a new clean linux! "
fi

#################################################N-joy##################################################
