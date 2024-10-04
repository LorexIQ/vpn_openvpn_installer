#!/bin/bash

print_peers() {
    echo "Список пользователей:"
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
        echo "Нет зарегистрированных пользователей."
        exit 1
    fi

    while true; do
        print_peers
        read -p "Выберите номер пользователя для получения конфигурации: " user_choice

        if [ "$user_choice" -ge 1 ] && [ "$user_choice" -le "${#users_list[@]}" ]; then
            username="${users_list[$((user_choice - 1))]}"
            break
        else
            echo "Ошибка: такого пользователя нет."
        fi
    done
}

get_download_link() {
    interface_address=$(awk -F'/' '{print $1}' "$rootVPN/interface")
    directory="$rootVPN/users/$username"

    echo "Ссылка для скачивания конфигурации:"
    echo "- Windown: scp root@$interface_address:$directory/$username.ovpn C:\\$username.ovpn"
    echo "- Linux: scp root@$interface_address:$directory/$username.ovpn /root/$username.ovpn"
}

rootVPN="/etc/openvpn"

users_list=()

list_peers
get_download_link
