#!/bin/bash
#################### x-ui-pro v2.4.3 @ github.com/GFW4Fun ##############################################
# Проверка root / Check root
[[ $EUID -ne 0 ]] && echo "not root!" && sudo su -

msg_ok() { echo -e "\e[1;42m $1 \e[0m";}
msg_err() { echo -e "\e[1;41m $1 \e[0m";}
msg_inf() { echo -e "\e[1;34m$1\e[0m";}
echo;msg_inf '           ___    _   _   _  ';msg_inf ' \/ __ | |  | __ |_) |_) / \ ';msg_inf ' /\    |_| _|_   |   | \ \_/ '; echo

# Глобальные переменные / Global variables
XUIDB="/etc/x-ui/x-ui.db";domain="";UNINSTALL="x";INSTALL="n";PNLNUM=1;CFALLOW="n";CLASH=0;CUSTOMWEBSUB=0
Pak=$(type apt &>/dev/null && echo "apt" || echo "yum")

# Проверка и установка UFW / Ensure UFW
ensure_ufw() {
    if ! command -v ufw >/dev/null 2>&1; then
        $Pak -y install ufw >/dev/null 2>&1
    fi
    ufw --force disable >/dev/null 2>&1 || true
}

# Очистка старых конфигов / Clean old configs
systemctl stop x-ui
rm -rf /etc/systemd/system/x-ui.service /usr/local/x-ui /etc/x-ui
rm -rf /etc/nginx/sites-enabled/* /etc/nginx/sites-available/* /etc/nginx/stream-enabled/*

# Генерация портов и путей / Port and path generation
get_port() { echo $(( ((RANDOM<<15)|RANDOM) % 49152 + 10000 )); }
gen_random_string() { local length="$1"; head -c 4096 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c "$length"; echo; }
check_free() { local port=$1; nc -z 127.0.0.1 $port &>/dev/null; return $?; }
make_port() { while true; do PORT=$(get_port); if ! check_free $PORT; then echo $PORT; break; fi; done; }

sub_port=$(make_port); panel_port=$(make_port); web_path=$(gen_random_string 10)
sub2singbox_path=$(gen_random_string 10); sub_path=$(gen_random_string 10)
json_path=$(gen_random_string 10); panel_path=$(gen_random_string 10)
ws_port=$(make_port); trojan_port=$(make_port)
ws_path=$(gen_random_string 10); trojan_path=$(gen_random_string 10)
xhttp_path=$(gen_random_string 10); config_username=$(gen_random_string 10)
config_password=$(gen_random_string 10); AUTODOMAIN="n"

# Парсинг аргументов / Parse arguments
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

# Полное удаление / Uninstall
UNINSTALL_XUI(){
	printf 'y\n' | x-ui uninstall
	rm -rf "/etc/x-ui/" "/usr/local/x-ui/" "/usr/bin/x-ui/"
	$Pak -y remove nginx nginx-common nginx-core nginx-full python3-certbot-nginx
	$Pak -y purge nginx nginx-common nginx-core nginx-full python3-certbot-nginx
	$Pak -y autoremove; $Pak -y autoclean
	rm -rf "/var/www/html/" "/etc/nginx/" "/usr/share/nginx/" 
}
if [[ ${UNINSTALL} == *"y"* ]]; then UNINSTALL_XUI; clear && msg_ok "Completely Uninstalled!" && exit 1; fi

# Авто домен / Auto domain
IP4_REGEX="^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$"
IP4=$(ip route get 8.8.8.8 2>&1 | grep -Po -- 'src \K\S*')
[[ $IP4 =~ $IP4_REGEX ]] || IP4=$(curl -s ipv4.icanhazip.com | tr -d '[:space:]')
if [[ ${AUTODOMAIN} == *"y"* ]]; then domain="${IP4}.cdn-one.org"; reality_domain="${IP4//./-}.cdn-one.org"; fi

while true; do if [[ -n "$domain" ]]; then break; fi; echo -en "Enter available subdomain (sub.domain.tld): " && read domain; done
domain=$(echo "$domain" | tr -d '[:space:]' )
SubDomain=$(echo "$domain" | sed 's/^[^ ]* \|\..*//g'); MainDomain=$(echo "$domain" | sed 's/.*\.\([^.]*\..*\)$/\1/')
if [[ "${SubDomain}.${MainDomain}" != "${domain}" ]] ; then MainDomain=${domain}; fi

while true; do if [[ -n "$reality_domain" ]]; then break; fi; echo -en "Enter available subdomain for REALITY (sub.domain.tld): " && read reality_domain; done
reality_domain=$(echo "$reality_domain" | tr -d '[:space:]' )
RealitySubDomain=$(echo "$reality_domain" | sed 's/^[^ ]* \|\..*//g'); RealityMainDomain=$(echo "$reality_domain" | sed 's/.*\.\([^.]*\..*\)$/\1/')
if [[ "${RealitySubDomain}.${RealityMainDomain}" != "${reality_domain}" ]] ; then RealityMainDomain=${reality_domain}; fi

# Установка пакетов / Install packages
if [[ ${INSTALL} == *"y"* ]]; then
         version=$(grep -oP '(?<=VERSION_ID=")[0-9]+' /etc/os-release)
         if [[ "$version" == "20" || "$version" == "22" ]]; then echo "Версия системы: Ubuntu $version"; fi
	$Pak -y update
	$Pak -y install curl wget jq bash sudo nginx-full certbot python3-certbot-nginx sqlite3 ufw
	systemctl daemon-reload && systemctl enable --now nginx
    ensure_ufw
fi
systemctl stop nginx 
fuser -k 80/tcp 80/udp 443/tcp 443/udp 2>/dev/null

# Получение IP / Get IPs
IP4_REGEX="^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$"
IP6_REGEX="([a-f0-9:]+:+)+[a-f0-9]+"
IP4=$(ip route get 8.8.8.8 2>&1 | grep -Po -- 'src \K\S*')
IP6=$(ip route get 2620:fe::fe 2>&1 | grep -Po -- 'src \K\S*')
[[ $IP4 =~ $IP4_REGEX ]] || IP4=$(curl -s ipv4.icanhazip.com);
[[ $IP6 =~ $IP6_REGEX ]] || IP6=$(curl -s ipv6.icanhazip.com);

# Проверка резолва авто домена / Resolve check
resolve_to_ip () { local host="$1"; local a; a=$(getent ahostsv4 "$host" 2>/dev/null | awk 'NR==1{print $1}'); [[ -n "$a" ]] && [[ "$a" == "$IP4" ]]; }
if [[ ${AUTODOMAIN} == *"y"* ]]; then
    if ! resolve_to_ip "$domain"; then msg_err "Auto-domain $domain does not resolve to this server IP ($IP4). Fix DNS/service and retry."; exit 1; fi
    if ! resolve_to_ip "$reality_domain"; then msg_err "Auto-domain $reality_domain does not resolve to this server IP ($IP4). Fix DNS/service and retry."; exit 1; fi
fi

# Выдача сертификатов / Get certificates
certbot certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email -d "$domain"
if [[ ! -d "/etc/letsencrypt/live/${domain}/" ]]; then systemctl start nginx >/dev/null 2>&1; msg_err "$domain SSL could not be generated! Check Domain/IP Or Enter new domain!" && exit 1; fi
certbot certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email -d "$reality_domain"
if [[ ! -d "/etc/letsencrypt/live/${reality_domain}/" ]]; then systemctl start nginx >/dev/null 2>&1; msg_err "$reality_domain SSL could not be generated! Check Domain/IP Or Enter new domain!" && exit 1; fi

# Очистка старых настроек x-ui / Clean old x-ui settings
if [[ -f $XUIDB ]]; then
	XUIPORT=$(sqlite3 -list $XUIDB 'SELECT "value" FROM settings WHERE "key"="webPort" LIMIT 1;' 2>&1)
	XUIPATH=$(sqlite3 -list $XUIDB 'SELECT "value" FROM settings WHERE "key"="webBasePath" LIMIT 1;' 2>&1)
if [[ $XUIPORT -gt 0 && $XUIPORT != "54321" && $XUIPORT != "2053" ]] && [[ ${#XUIPORT} -gt 4 ]]; then
	sqlite3 $XUIDB <<EOF
	DELETE FROM "settings" WHERE ( "key"="webCertFile" ) OR ( "key"="webKeyFile" ); 
	INSERT INTO "settings" ("key", "value") VALUES ("webCertFile",  "");
	INSERT INTO "settings" ("key", "value") VALUES ("webKeyFile", "");
EOF
fi
fi

# Сертификаты для nginx / Certs for nginx
mkdir -p /root/cert/${domain}
chmod 755 /root/cert/${domain}
ln -sf /etc/letsencrypt/live/${domain}/fullchain.pem /root/cert/${domain}/fullchain.pem
ln -sf /etc/letsencrypt/live/${domain}/privkey.pem /root/cert/${domain}/privkey.pem

# Stream конфиг / Stream config
mkdir -p /etc/nginx/stream-enabled
cat > "/etc/nginx/stream-enabled/stream.conf" << EOF
map \$ssl_preread_server_name \$sni_name {
    hostnames;
    ${reality_domain}      xray;
    ${domain}           www;
    default              xray;
}
upstream xray { server 127.0.0.1:8443; }
upstream www { server 127.0.0.1:7443; }
server {
    proxy_protocol on;
    listen 443;
    listen [::]:443;
    proxy_pass \$sni_name;
    ssl_preread on;
}
EOF

grep -xqFR "stream { include /etc/nginx/stream-enabled/*.conf; }" /etc/nginx/* ||echo "stream { include /etc/nginx/stream-enabled/*.conf; }" >> /etc/nginx/nginx.conf
grep -xqFR "load_module modules/ngx_stream_module.so;" /etc/nginx/* || sed -i '1s/^/load_module \/usr\/lib\/nginx\/modules\/ngx_stream_module.so; /' /etc/nginx/nginx.conf
grep -xqFR "load_module modules/ngx_stream_geoip2_module.so;" /etc/nginx* || sed -i '2s/^/load_module \/usr\/lib\/nginx\/modules\/ngx_stream_geoip2_module.so; /' /etc/nginx/nginx.conf
grep -xqFR "worker_rlimit_nofile 16384;" /etc/nginx/* ||echo "worker_rlimit_nofile 16384;" >> /etc/nginx/nginx.conf
sed -i "/worker_connections/c\worker_connections 4096;" /etc/nginx/nginx.conf

# Nginx sites / Nginx sites
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
	root /var/www/html/;
	ssl_protocols TLSv1.2 TLSv1.3;
	ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
	ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
	include /etc/nginx/snippets/includes.conf;
}
EOF

cat > "/etc/nginx/snippets/includes.conf" << EOF
location /${panel_path}/ { proxy_pass https://127.0.0.1:${panel_port}; }
location /${panel_path} { proxy_pass https://127.0.0.1:${panel_port}; }
# sub2sing-box, web sub, subscriptions, xhttp, xray config path...
EOF

cat > "/etc/nginx/sites-available/${reality_domain}" << EOF
server {
	server_tokens off;
	server_name ${reality_domain};
	listen 9443 ssl http2;
	ssl_certificate /etc/letsencrypt/live/$reality_domain/fullchain.pem;
	ssl_certificate_key /etc/letsencrypt/live/$reality_domain/privkey.pem;
	include /etc/nginx/snippets/includes.conf;
}
EOF

if [[ -f "/etc/nginx/sites-available/${domain}" ]]; then
	unlink "/etc/nginx/sites-enabled/default" >/dev/null 2>&1
	ln -s "/etc/nginx/sites-available/${domain}" "/etc/nginx/sites-enabled/"
    ln -s "/etc/nginx/sites-available/${reality_domain}" "/etc/nginx/sites-enabled/"
	ln -s "/etc/nginx/sites-available/80.conf" "/etc/nginx/sites-enabled/"
else
	msg_err "${domain} nginx config not exist!" && exit 1
fi

if [[ $(nginx -t 2>&1 | grep -o 'successful') != "successful" ]]; then
    msg_err "nginx config is not ok!" && exit 1
else
	systemctl start nginx 
fi

# URI / URIs
sub_uri=https://${domain}/${sub_path}/
json_uri=https://${domain}/${web_path}?name=
shor=($(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8) $(openssl rand -hex 8))

# Запрос на RU маршрутизацию / Ask for RU routing
read -p "Add Russian segment routing rules? y/n: " RU_ROUTING
if [[ "$RU_ROUTING" == "y" || "$RU_ROUTING" == "Y" ]]; then
  RU_RULE="true"
else
  RU_RULE="false"
fi

# Обновление БД X-UI / Update X-UI DB
UPDATE_XUIDB(){
if [[ -f $XUIDB ]]; then
        x-ui stop
        output=$(/usr/local/x-ui/bin/xray-linux-amd64 x25519)
        private_key=$(echo "$output" | grep "^PrivateKey:" | awk '{print $2}')
        public_key=$(echo "$output" | grep "^Password" | awk '{print $3}')
        client_id=$(/usr/local/x-ui/bin/xray-linux-amd64 uuid)
        client_id2=$(/usr/local/x-ui/bin/xray-linux-amd64 uuid)
        client_id3=$(/usr/local/x-ui/bin/xray-linux-amd64 uuid)
        trojan_pass=$(gen_random_string 10)
        emoji_flag=$(LC_ALL=en_US.UTF-8 curl -s https://ipwho.is/ | jq -r '.flag.emoji')

        # Sniffing включен по умолчанию / Sniffing enabled by default
        SNIFFING='{"enabled":true,"destOverride":["http","tls","quic","fakedns"],"metadataOnly":false,"routeOnly":false}'

        sqlite3 $XUIDB <<EOF
INSERT OR REPLACE INTO "settings" ("key","value") VALUES ("subPort", '${sub_port}');
INSERT OR REPLACE INTO "settings" ("key","value") VALUES ("subPath", '/${sub_path}/');
INSERT OR REPLACE INTO "settings" ("key","value") VALUES ("subURI", '${sub_uri}');
INSERT OR REPLACE INTO "settings" ("key","value") VALUES ("subJsonPath", '${json_path}');
INSERT OR REPLACE INTO "settings" ("key","value") VALUES ("subJsonURI", '${json_uri}');
INSERT OR REPLACE INTO "settings" ("key","value") VALUES ("subEnable", 'true');
INSERT OR REPLACE INTO "settings" ("key","value") VALUES ("webCertFile", '');
INSERT OR REPLACE INTO "settings" ("key","value") VALUES ("webKeyFile", '');
INSERT OR REPLACE INTO "settings" ("key","value") VALUES ("webPort", '${panel_port}');
INSERT OR REPLACE INTO "settings" ("key","value") VALUES ("webBasePath", '${panel_path}');
INSERT OR REPLACE INTO "client_traffics" ("inbound_id","enable","email","up","down","expiry_time","total","reset") VALUES (1,'1','first','0','0','0','0','0');
INSERT OR REPLACE INTO "client_traffics" ("inbound_id","enable","email","up","down","expiry_time","total","reset") VALUES (2,'1','first_1','0','0','0','0','0');
INSERT OR REPLACE INTO "client_traffics" ("inbound_id","enable","email","up","down","expiry_time","total","reset") VALUES (3,'1','firstX','0','0','0','0','0');
INSERT OR REPLACE INTO "client_traffics" ("inbound_id","enable","email","up","down","expiry_time","total","reset") VALUES (4,'1','firstT','0','0','0','0','0');

# Reality inbound with tgId:0 and sniffing enabled
INSERT OR REPLACE INTO "inbounds" ("id","user_id","up","down","total","remark","enable","expiry_time","listen","port","protocol","settings","stream_settings","tag","sniffing") VALUES (
1,'1','0','0','0','${emoji_flag} reality','1','0','','8443','vless',
'{ "clients": [{"id":"${client_id}","flow":"xtls-rprx-vision","email":"first","limitIp":0,"totalGB":0,"expiryTime":0,"enable":true,"tgId":0,"subId":"first","reset":0,"created_at":1756726925000,"updated_at":1756726925000}],"decryption":"none","fallbacks":[] }',
'{ "network": "tcp","security": "reality","externalProxy":[{"forceTls":"same","dest":"${reality_domain}","port":443,"remark":""}],"realitySettings":{"show":false,"xver":0,"target":"127.0.0.1:9443","serverNames":["${reality_domain}"],"privateKey":"${private_key}","minClient":"","maxClient":"","maxTimediff":0,"shortIds":["${shor[0]}","${shor[1]}","${shor[2]}","${shor[3]}","${shor[4]}","${shor[5]}","${shor[6]}","${shor[7]}"],"settings":{"publicKey":"${public_key}","fingerprint":"chrome","serverName":"","spiderX":"/"}},"tcpSettings":{"acceptProxyProtocol":true,"header":{"type":"none"}} }',
'inbound-8443','${SNIFFING}'
);
# WS inbound
INSERT OR REPLACE INTO "inbounds" ("id","user_id","up","down","total","remark","enable","expiry_time","listen","port","protocol","settings","stream_settings","tag","sniffing") VALUES (
2,'1','0','0','0','${emoji_flag} ws','1','0','','${ws_port}','vless',
'{ "clients": [{"id":"${client_id2}","flow":"","email":"first_1","limitIp":0,"totalGB":0,"expiryTime":0,"enable":true,"tgId":0,"subId":"first","reset":0,"created_at":1756726925000,"updated_at":1756726925000}],"decryption":"none","fallbacks":[] }',
'{ "network":"ws","security":"none","externalProxy":[{"forceTls":"tls","dest":"${domain}","port":443,"remark":""}],"wsSettings":{"acceptProxyProtocol":false,"path":"/${ws_port}/${ws_path}","host":"${domain}","headers":{}} }',
'inbound-${ws_port}','${SNIFFING}'
);
# XHTTP inbound
INSERT OR REPLACE INTO "inbounds" ("id","user_id","up","down","total","remark","enable","expiry_time","listen","port","protocol","settings","stream_settings","tag","sniffing") VALUES (
3,'1','0','0','0','${emoji_flag} xhttp','0','0','/dev/shm/uds2023.sock,0666','0','vless',
'{ "clients": [{"id":"${client_id3}","flow":"","email":"firstX","limitIp":0,"totalGB":0,"expiryTime":0,"enable":true,"tgId":0,"subId":"first","reset":0,"created_at":1756726925000,"updated_at":1756726925000}],"decryption":"none","fallbacks":[] }',
'{ "network":"xhttp","security":"none","externalProxy":[{"forceTls":"tls","dest":"${domain}","port":443,"remark":""}],"xhttpSettings":{"path":"/${xhttp_path}","host":"${domain}","headers":{},"scMaxBufferedPosts":30,"scMaxEachPostBytes":"1000000","noSSEHeader":false,"xPaddingBytes":"100-1000","mode":"packet-up"},"sockopt":{"acceptProxyProtocol":false,"tcpFastOpen":true,"mark":0,"tproxy":"off","tcpMptcp":true,"tcpNoDelay":true,"domainStrategy":"UseIP","tcpMaxSeg":1440,"dialerProxy":"","tcpKeepAliveInterval":0,"tcpKeepAliveIdle":300,"tcpUserTimeout":10000,"tcpcongestion":"bbr","V6Only":false,"tcpWindowClamp":600,"interface":""} }',
'inbound-/dev/shm/uds2023.sock,0666:0|','${SNIFFING}'
);
# Trojan gRPC inbound
INSERT OR REPLACE INTO "inbounds" ("id","user_id","up","down","total","remark","enable","expiry_time","listen","port","protocol","settings","stream_settings","tag","sniffing") VALUES (
4,'1','0','0','0','${emoji_flag} trojan-grpc','1','0','','${trojan_port}','trojan',
'{ "clients": [{"comment":"","created_at":1756726925000,"email":"firstT","enable":true,"expiryTime":0,"limitIp":0,"password":"${trojan_pass}","reset":0,"subId":"first","tgId":0,"totalGB":0,"updated_at":1756726925000}],"fallbacks":[] }',
'{ "network":"grpc","security":"none","externalProxy":[{"forceTls":"tls","dest":"${domain}","port":443,"remark":""}],"grpcSettings":{"serviceName":"/${trojan_port}/${trojan_path}","authority":"${domain}","multiMode":false} }',
'inbound-${trojan_port}','${SNIFFING}'
);
EOF
        /usr/local/x-ui/x-ui setting -username "${config_username}" -password "${config_password}" -port "${panel_port}" -webBasePath "${panel_path}"
        /usr/local/x-ui/x-ui cert -webCert "/root/cert/${domain}/fullchain.pem" -webCertKey "/root/cert/${domain}/privkey.pem"
        x-ui start
else
        msg_err "x-ui.db file not exist! Maybe x-ui isn't installed." && exit 1;
fi
}

# Установка панели / Install panel
arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64) echo 'amd64' ;;
        i*86 | x86) echo '386' ;;
        armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
        *) echo 'amd64' ;;
    esac
}
install_panel() {
apt-get update && apt-get install -y -q wget curl tar tzdata
    cd /usr/local/
    tag_version="v3.8.0"
    wget -N -O /usr/local/x-ui-linux-$(arch).tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
    tar zxvf x-ui-linux-$(arch).tar.gz; rm x-ui-linux-$(arch).tar.gz -f
    cd x-ui; chmod +x x-ui x-ui.sh
    mv -f /usr/bin/x-ui-temp /usr/bin/x-ui 2>/dev/null || true
    cp -f x-ui.service.debian /etc/systemd/system/x-ui.service
    systemctl daemon-reload; systemctl enable x-ui; systemctl start x-ui
    echo -e "${green}x-ui ${tag_version} installation finished${plain}"
}

if systemctl is-active --quiet x-ui; then
	x-ui restart
else
    install_panel	
	UPDATE_XUIDB
fi

# Тюнинг системы / System tuning
apt-get install -yqq --no-install-recommends ca-certificates
echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf
sysctl -p

# sub2sing-box / sub2sing-box
if pgrep -x "sub2sing-box" > /dev/null; then pkill -x "sub2sing-box"; fi
if [ -f "/usr/bin/sub2sing-box" ]; then rm -f /usr/bin/sub2sing-box; fi
wget -P /root/ https://github.com/legiz-ru/sub2sing-box/releases/download/v0.0.9/sub2sing-box_0.0.9_linux_amd64.tar.gz
tar -xvzf /root/sub2sing-box_0.0.9_linux_amd64.tar.gz -C /root/ --strip-components=1 sub2sing-box_0.0.9_linux_amd64/sub2sing-box
mv /root/sub2sing-box /usr/bin/; chmod +x /usr/bin/sub2sing-box
su -c "/usr/bin/sub2sing-box server --bind 127.0.0.1 --port 8080 & disown" root

# Fake site / Fake site
FAKE_SITE_TMP=$(mktemp -d)
if wget -qO "$FAKE_SITE_TMP/repo.tar.gz" "https://github.com/mozaroc/3x-ui-pro/archive/refs/heads/main.tar.gz" \
	&& tar -xzf "$FAKE_SITE_TMP/repo.tar.gz" -C "$FAKE_SITE_TMP" --strip-components=3 "3x-ui-pro-main/assets/fake-sites"; then
	FAKE_SITES=("$FAKE_SITE_TMP"/site-*/)
	FAKE_SITE="${FAKE_SITES[$((RANDOM % ${#FAKE_SITES[@]}))]}"
	mkdir -p /var/www/html; rm -rf /var/www/html/*; cp -a "$FAKE_SITE". /var/www/html/
	msg_ok "Fake site installed successfully!"
fi
rm -rf "$FAKE_SITE_TMP"

# Web sub page / Web sub page
DEST_DIR_SUB_PAGE="/var/www/subpage"
mkdir -p "$DEST_DIR_SUB_PAGE"
curl -L "${URL_CLASH_SUB[$CLASH]}" -o "$DEST_DIR_SUB_PAGE/clash.yaml"
curl -L "${URL_SUB_PAGE[$CUSTOMWEBSUB]}" -o "$DEST_DIR_SUB_PAGE/index.html"

# Cron / Cron
crontab -l | grep -v "certbot\|x-ui\|cloudflareips" | crontab -
(crontab -l 2>/dev/null; echo '@reboot /usr/bin/sub2sing-box server --bind 127.0.0.1 --port 8080 > /dev/null 2>&1') | crontab -
(crontab -l 2>/dev/null; echo '@daily x-ui restart > /dev/null 2>&1 && nginx -s reload;') | crontab -

# UFW / UFW
if command -v ufw >/dev/null 2>&1; then
    ufw disable
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
fi

# Вывод информации / Show info
if systemctl is-active --quiet x-ui; then clear
	printf '0\n' | x-ui | grep --color=never -i ':'
	msg_inf "X-UI Secure Panel: https://${domain}/${panel_path}/"
 	echo -e "Username:  ${config_username} \n" 
	echo -e "Password:  ${config_password} \n" 
else
	msg_err "sqlite and x-ui to be checked, try on a new clean linux! "
fi
#################################################N-joy##################################################
