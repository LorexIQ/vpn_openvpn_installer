#!/bin/bash

is_valid_username() {
    echo "$1" | grep -qE '^[a-zA-Z0-9_]+$'
}

create_users_folder() {
    users_directory="$rootVPN/users"
    if [ ! -d "$users_directory" ]; then
        mkdir "$users_directory"
    fi
}

restart_server() {
    echo "Перезапуск сервера OpenVPN..."
    systemctl restart openvpn@server

    status=$(systemctl is-active openvpn@server)

    if [ "$status" = "active" ]; then
        echo "Статус сервера: успешно перезапущен"
    else
        echo "Статус сервера: ошибка перезапуска"
        exit 1
    fi
}

create_client_config() {
    interface_address=$(awk -F'/' '{print $1}' "$rootVPN/interface")
    listen_port=1194
    local user_key=$(sed -n '/-----BEGIN PRIVATE KEY-----/,/-----END PRIVATE KEY-----/p' "$directory/$username.key")
    local user_crt=$(sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' "$directory/$username.crt")
    local ca_crt=$(sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' "$directory/ca.crt")
    local ta_crt=$(sed -n '/-----BEGIN OpenVPN Static key V1-----/,/-----END OpenVPN Static key V1-----/p' "$directory/ta.key")

    cat << EOF > "$directory/$username.ovpn"
client
dev tun
proto udp
remote $interface_address $listen_port
resolv-retry infinite
key-direction 1
redirect-gateway def1
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
verb 3

<key>
$user_key
</key>

<cert>
$user_crt
</cert>

<ca>
$ca_crt
</ca>

<tls-auth>
$ta_crt
</tls-auth>
EOF
}

get_download_link() {
    echo "Ссылка для скачивания конфигурации:"
    echo "- Windown: scp root@$interface_address:$directory/$username.ovpn C:\\$username.ovpn"
    echo "- Linux: scp root@$interface_address:$directory/$username.ovpn /root/$username.ovpn"
}

name_input() {
    while true; do
        read -p "Введите имя нового пользователя: " username

        if is_valid_username "$username"; then
            directory="$users_directory/$username"
            if [ ! -d "$directory" ]; then
                mkdir "$directory"

                echo "Генерация пары ключей пользователя..."
                cd "$rootVPN/easy-rsa" || exit
                ./easyrsa build-client-full "$username" nopass > /dev/null 2>&1

                cp "$rootVPN/easy-rsa/pki/ca.crt" "$directory"
                cp "$rootVPN/easy-rsa/pki/ta.key" "$directory"
                cp "$rootVPN/easy-rsa/pki/issued/$username.crt" "$directory"
                cp "$rootVPN/easy-rsa/pki/private/$username.key" "$directory"

                create_client_config

                echo "Пользователь $username успешно создан."
                break
            else
                echo "Пользователь $username уже существует."
            fi
        else
            echo "Недопустимое имя пользователя. Доступны только a-z, 0-9 и _. Попробуйте снова."
        fi
    done
}

rootVPN="/etc/openvpn"

create_users_folder
name_input
restart_server
get_download_link
