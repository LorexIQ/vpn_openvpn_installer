#!/bin/bash

print_peers() {
    echo "Выберите пользователя для удаления:"
    for i in "${!users_list[@]}"; do
        echo "$((i+1)). ${users_list[$i]}"
    done
}

list_peers() {
    for dir in "$rootVPN/users"/*; do
        if [ -d "$dir" ]; then
            users_list+=("$(basename "$dir")")
        fi
    done

    if [ ${#users_list[@]} -eq 0 ]; then
        echo "Нет доступных для удаления пользователей."
        exit 1
    fi

    while true; do
        print_peers
        read -p "Выберите номер пользователя для удаления: " user_choice

        if [ "$user_choice" -ge 1 ] && [ "$user_choice" -le "${#users_list[@]}" ]; then
            username="${users_list[$((user_choice - 1))]}"
            break
        else
            echo "Ошибка: такого пользователя нет."
        fi
    done
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

remove_peer() {
  cd "$rootVPN/easy-rsa" || exit 1

  echo "Отзыв сертификатов..."
  yes | ./easyrsa --batch revoke "$username" > /dev/null 2>&1

  echo "Обновление списка отозванных сертификатов..."
  ./easyrsa gen-crl > /dev/null 2>&1
  cp "$rootVPN/easy-rsa/pki/crl.pem" "$rootVPN"

    user_directory="$rootVPN/users/$username"
    if [ -d "$user_directory" ]; then
        rm -rf "$user_directory"
        echo "Пользователь $username успешно удалён."
    else
        echo "Ключи пользователя $username не найдены."
    fi
}

rootVPN="/etc/openvpn"

users_list=()

list_peers
remove_peer
restart_server
