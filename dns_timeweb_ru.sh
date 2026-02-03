#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_timeweb_ru_info='Timeweb.ru (Старый API)
Site: Timeweb.ru
Docs: API документация из timeweb.ru.txt
Options:
  TW_Login - Логин аккаунта (например: cn12345)
  TW_Token - Bearer токен, полученный через авторизацию
  TW_AppKey - Ключ API (appkey), полученный в поддержке
Issues: github.com/acmesh-official/acme.sh/issues
'

TW_Api="https://api.timeweb.ru/v1.2"

################  Public functions ################

# Adds an ACME DNS-01 challenge DNS TXT record via the Timeweb.ru API.
dns_timeweb_ru_add() {
  _debug "$(__green "Timeweb.ru DNS API"): \"dns_timeweb_ru_add\" started."

  _timeweb_ru_set_acme_fqdn "$1" || return 1
  _timeweb_ru_set_acme_txt "$2" || return 1
  _timeweb_ru_check_credentials || return 1
  _timeweb_ru_split_acme_fqdn || return 1
  _timeweb_ru_dns_txt_add || return 1

  _debug "$(__green "Timeweb.ru DNS API"): \"dns_timeweb_ru_add\" finished."
}

# Removes a DNS TXT record via the Timeweb.ru API.
dns_timeweb_ru_rm() {
  _debug "$(__green "Timeweb.ru DNS API"): \"dns_timeweb_ru_rm\" started."

  _timeweb_ru_set_acme_fqdn "$1" || return 1
  _timeweb_ru_set_acme_txt "$2" || return 1
  _timeweb_ru_check_credentials || return 1
  _timeweb_ru_split_acme_fqdn || return 1
  _timeweb_ru_get_dns_txt || return 1
  _timeweb_ru_dns_txt_remove || return 1

  _debug "$(__green "Timeweb.ru DNS API"): \"dns_timeweb_ru_rm\" finished."
}

################  Private functions ################

_timeweb_ru_set_acme_fqdn() {
  Acme_Fqdn=$1
  _debug "Setting ACME DNS-01 challenge FQDN \"$Acme_Fqdn\"."
  [ -z "$Acme_Fqdn" ] && {
    _err "ACME DNS-01 challenge FQDN is empty."
    return 1
  }
  return 0
}

_timeweb_ru_set_acme_txt() {
  Acme_Txt=$1
  _debug "Setting ACME TXT value to \"$Acme_Txt\"."
  [ -z "$Acme_Txt" ] && {
    _err "ACME TXT value is empty."
    return 1
  }
  return 0
}

# Проверяем все необходимые учетные данные
_timeweb_ru_check_credentials() {
  _debug "Checking Timeweb.ru API credentials."

  TW_Login="${TW_Login:-$(_readaccountconf_mutable TW_Login)}"
  TW_Token="${TW_Token:-$(_readaccountconf_mutable TW_Token)}"
  TW_AppKey="${TW_AppKey:-$(_readaccountconf_mutable TW_AppKey)}"

  [ -z "$TW_Login" ] && {
    _err "Timeweb.ru login is not set."
    _err "Please set TW_Login to your account login (e.g., cn12345)."
    return 1
  }

  [ -z "$TW_Token" ] && {
    _err "Timeweb.ru token is not set."
    _err "Get token via: curl -X POST \"https://api.timeweb.ru/v1.2/access\" -H \"x-app-key: YOUR_APPKEY\" -u 'LOGIN:PASSWORD'"
    return 1
  }

  [ -z "$TW_AppKey" ] && {
    _err "Timeweb.ru appkey is not set."
    _err "Get appkey from Timeweb support team."
    return 1
  }

  # Сохраняем учетные данные
  _saveaccountconf_mutable TW_Login "$TW_Login"
  _saveaccountconf_mutable TW_Token "$TW_Token"
  _saveaccountconf_mutable TW_AppKey "$TW_AppKey"
  
  return 0
}

# Делим FQDN на домен и поддомен
_timeweb_ru_split_acme_fqdn() {
  _debug "Splitting \"$Acme_Fqdn\" into domain and subdomain."

  # Получаем список доменов аккаунта
  if ! _timeweb_ru_list_domains; then
    _err "Failed to get domains list."
    return 1
  fi

  # Ищем домен в списке
  for domain in $TW_Domains_List; do
    if echo ".$Acme_Fqdn" | grep -qi "\.$domain\$"; then
      TW_Main_Domain="$domain"
      # Извлекаем поддомен (всё что перед основным доменом)
      TW_Subdomain="${Acme_Fqdn%.$domain}"
      
      # Если поддомен начинается с "_acme-challenge.", убираем это
      TW_Subdomain="${TW_Subdomain#_acme-challenge.}"
      # Если после этого осталась пустая строка или только точка, делаем null
      if [ -z "$TW_Subdomain" ] || [ "$TW_Subdomain" = "." ]; then
        TW_Subdomain="null"
      fi
      
      _debug "Found domain: $TW_Main_Domain, subdomain: $TW_Subdomain"
      return 0
    fi
  done

  _err "Domain for \"$Acme_Fqdn\" not found in your account."
  return 1
}

# Получаем список доменов аккаунта
_timeweb_ru_list_domains() {
  _debug "Getting domains list for account $TW_Login"

  export _H1="x-app-key: $TW_AppKey"
  export _H2="Authorization: Bearer $TW_Token"

  # Получаем информацию о сайтах, в которой есть список доменов
  if ! response=$(_get "https://api.timeweb.ru/v1.1/sites/$TW_Login"); then
    _err "Failed to get sites list from API."
    return 1
  fi

  # Извлекаем домены из ответа
  # Ответ содержит массив объектов с полем "domains"
  TW_Domains_List=$(echo "$response" | grep -o '"domains":\[[^]]*\]' | grep -o '"[^"]*"' | tr -d '"' | tr '\n' ' ')
  
  if [ -z "$TW_Domains_List" ]; then
    _err "No domains found in account."
    return 1
  fi

  _debug "Domains found: $TW_Domains_List"
  return 0
}

# Ищем существующую TXT запись
_timeweb_ru_get_dns_txt() {
  _debug "Looking for existing TXT record with value \"$Acme_Txt\""

  export _H1="x-app-key: $TW_AppKey"
  export _H2="Authorization: Bearer $TW_Token"

  # Получаем все DNS записи домена
  if ! response=$(_get "$TW_Api/accounts/$TW_Login/domains/$TW_Main_Domain/user-records?limit=100"); then
    _err "Failed to get DNS records."
    return 1
  fi

  # Парсим ответ для поиска TXT записи
  # Ищем запись с типом TXT, нужным subdomain и значением
  records=$(echo "$response" | sed 's/},{/}\n{/g')
  
  while IFS= read -r record; do
    # Проверяем тип записи
    if echo "$record" | grep -q '"type":"TXT"'; then
      # Проверяем subdomain
      subdomain=$(echo "$record" | grep -o '"subdomain":"[^"]*"' | cut -d'"' -f4)
      if [ "$subdomain" = "$TW_Subdomain" ] || [ "$subdomain" = "null" -a -z "$TW_Subdomain" ]; then
        # Проверяем значение
        value=$(echo "$record" | grep -o '"value":"[^"]*"' | cut -d'"' -f4)
        if [ "$value" = "$Acme_Txt" ]; then
          # Извлекаем ID записи
          TW_Dns_Txt_Id=$(echo "$record" | grep -o '"id":[0-9]*' | cut -d: -f2)
          if [ -n "$TW_Dns_Txt_Id" ]; then
            _debug "Found TXT record with ID: $TW_Dns_Txt_Id"
            return 0
          fi
        fi
      fi
    fi
  done <<EOF
$records
EOF

  _err "TXT record not found."
  return 1
}

# Добавляем TXT запись
_timeweb_ru_dns_txt_add() {
  _debug "Adding TXT record via Timeweb.ru API"

  export _H1="x-app-key: $TW_AppKey"
  export _H2="Authorization: Bearer $TW_Token"
  export _H3="Content-Type: application/json"

  # Формируем данные согласно API спецификации
  if [ "$TW_Subdomain" = "null" ]; then
    data="{\"data\":{\"value\":\"$Acme_Txt\"},\"type\":\"TXT\"}"
  else
    data="{\"data\":{\"subdomain\":\"$TW_Subdomain\",\"value\":\"$Acme_Txt\"},\"type\":\"TXT\"}"
  fi

  _debug "Request data: $data"

  if ! response=$(_post "$data" "$TW_Api/accounts/$TW_Login/domains/$TW_Main_Domain/user-records/"); then
    _err "Failed to add TXT record."
    return 1
  fi

  # Извлекаем ID новой записи
  TW_Dns_Txt_Id=$(echo "$response" | grep -o '"id":[0-9]*' | cut -d: -f2)
  
  if [ -z "$TW_Dns_Txt_Id" ]; then
    _err "Failed to get record ID from response."
    _debug "Response: $response"
    return 1
  fi

  _debug "TXT record added with ID: $TW_Dns_Txt_Id"
  return 0
}

# Удаляем TXT запись
_timeweb_ru_dns_txt_remove() {
  _debug "Removing TXT record with ID: $TW_Dns_Txt_Id"

  export _H1="x-app-key: $TW_AppKey"
  export _H2="Authorization: Bearer $TW_Token"

  if ! response=$(_post "" "$TW_Api/accounts/$TW_Login/domains/$TW_Main_Domain/user-records/$TW_Dns_Txt_Id/" "" "DELETE"); then
    _err "Failed to delete TXT record."
    return 1
  fi

  _debug "TXT record removed successfully"
  return 0
}