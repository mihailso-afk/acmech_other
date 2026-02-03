Site:Timeweb.com
Docs:https://timeweb.com/ru/docs/publichnyj-api-timeweb/metody-api-dlya-virtualnogo-hostinga/

Options:
export TW_Login="cn12345"
export TW_Token="ваш_токен"
export TW_AppKey="ваш_appkey"

# Использование с acme.sh
acme.sh --issue --dns dns_timeweb_ru -d example.com
