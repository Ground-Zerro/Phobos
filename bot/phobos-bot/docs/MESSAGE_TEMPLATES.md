# Message Templates API Documentation

This document describes all message templates used in Phobos-Bot, their purpose, available variables, and usage examples.

## Overview

Message templates are stored in the `message_templates` database table and support variable substitution using the `{{variable_name}}` syntax. Templates can be updated without code changes, providing flexibility for localization and customization.

## Template Structure

Each template has the following properties:
- **message_key**: Unique identifier for the template
- **template_text**: Text with optional `{{variable}}` placeholders
- **language_code**: Language identifier (default: 'ru')
- **version**: Template version number
- **created_at**: Creation timestamp
- **updated_at**: Last modification timestamp

## Common Variables

These variables are used across multiple templates:

| Variable | Description | Example Value |
|----------|-------------|---------------|
| `{{bot_name}}` | Name of the bot | "Phobos-Bot" |
| `{{username}}` | User's Telegram username | "john_doe" |
| `{{client_name}}` | VPN client configuration name | "john_doe" or "123456789" |
| `{{status}}` | Connection status | "🟢 Активно" / "🔴 Не активно" / "⚪ Никогда не подключался" |
| `{{last_handshake}}` | Time since last handshake | "15 сек. назад" / "5 мин. назад" / "—" |
| `{{transfer}}` | Data transfer statistics | "↓ 150.25 MB / ↑ 45.10 MB" / "—" |
| `{{expiration_date}}` | Premium expiration date | "2025-12-31" / "Бессрочно" |

## Bot Configuration Templates

### bot_name
**Purpose**: Display name of the bot

**Variables**: None

**Default**: `Phobos-Bot`

**Usage**: Referenced in welcome messages and information displays

---

## Command Descriptions

These templates define command descriptions shown in Telegram's command menu.

### command_start_description
**Purpose**: Description for `/start` command

**Variables**: None

**Example**: `Начать работу с ботом`

### command_create_description
**Purpose**: Description for `/create` command

**Variables**: None

**Example**: `Создать VPN-подключение`

### command_stat_description
**Purpose**: Description for `/stat` command

**Variables**: None

**Example**: `Статистика подключения`

### command_delete_description
**Purpose**: Description for `/delete` command

**Variables**: None

**Example**: `Удалить конфигурацию`

### command_info_description
**Purpose**: Description for `/info` command

**Variables**: None

**Example**: `Информация о сервисе`

### command_selfhost_description
**Purpose**: Description for `/selfhost` command

**Variables**: None

**Example**: `Инструкция по self-hosting`

### command_premium_description
**Purpose**: Description for `/premium` command

**Variables**: None

**Example**: `Информация о премиум-статусе`

### command_help_description
**Purpose**: Description for `/help` command

**Variables**: None

**Example**: `Помощь по использованию`

### command_feedback_description
**Purpose**: Description for `/feedback` command

**Variables**: None

**Example**: `Отправить обратную связь`

---

## Welcome and Start Messages

### start_welcome
**Purpose**: Welcome message shown when user executes `/start`

**Variables**:
- `{{bot_name}}` - Name of the bot
- `{{max_clients}}` - Maximum number of basic clients
- `{{available_slots}}` - Currently available slots
- `{{watchdog_threshold_hours}}` - Hours before inactive config is deleted
- `{{max_test_duration_hours}}` - Maximum test duration in hours

**Example**:
```
Добро пожаловать в {{bot_name}}!

Этот бот предоставляет доступ к VPN-сервису на базе WireGuard.

📊 Текущее состояние сервера:
• Максимум пользователей: {{max_clients}}
• Доступно слотов: {{available_slots}}

⏱️ Ограничения для бесплатных пользователей:
• Автоудаление при неактивности: {{watchdog_threshold_hours}} часов
• Максимальный срок тестирования: {{max_test_duration_hours}} часов

Используйте /create для создания подключения.
```

---

## Create Command Templates

### create_success
**Purpose**: Successful configuration creation message

**Variables**:
- `{{download_link}}` - Installation script download command
- `{{expiration_info}}` - Token expiration information

**Example**:
```
✅ Конфигурация успешно создана!

Выполните следующую команду на вашем роутере:
{{download_link}}

{{expiration_info}}
```

### create_error
**Purpose**: Error message when configuration creation fails

**Variables**: None

**Example**: `❌ Произошла ошибка при создании конфигурации. Попробуйте позже.`

### create_no_link
**Purpose**: Message when installation link cannot be extracted

**Variables**: None

**Example**: `⚠️ Конфигурация создана, но не удалось получить ссылку для установки.`

### create_exists
**Purpose**: Message when configuration already exists, requesting confirmation

**Variables**:
- `{{status}}` - Current connection status
- `{{last_handshake}}` - Time since last handshake
- `{{transfer}}` - Transfer statistics

**Example**:
```
⚠️ У вас уже есть активная конфигурация.

Текущий статус:
• Статус: {{status}}
• Последний handshake: {{last_handshake}}
• Трафик: {{transfer}}

Пересоздать конфигурацию? Текущая будет удалена.
```

### create_decline
**Purpose**: Message when user declines configuration recreation

**Variables**: None

**Example**: `✅ Создание нового подключения отменено. Текущее подключение остаётся активным.`

### create_rate_limited
**Purpose**: Message when user hits rate limit

**Variables**: None

**Example**: `⏳ Пожалуйста, подождите минуту перед следующим запросом.`

### test_limit_exceeded
**Purpose**: Message when basic user's test duration has expired

**Variables**: None

**Example**:
```
⏱️ Превышен лимит времени тестирования.

Для продолжения использования сервиса оформите премиум-подписку.
Используйте /premium для получения информации.
```

### restricted_new_users
**Purpose**: Message when new user registration is restricted

**Variables**: None

**Example**:
```
🚫 Регистрация новых пользователей временно ограничена.

Попробуйте позже или свяжитесь с администратором.
```

---

## Stat Command Templates

### stat_header
**Purpose**: Statistics display header

**Variables**:
- `{{status}}` - Connection status
- `{{last_handshake}}` - Time since last handshake
- `{{transfer}}` - Transfer statistics
- `{{time_remaining}}` - Remaining test time (for basic users)

**Example**:
```
📊 Статистика подключения

• Статус: {{status}}
• Последний handshake: {{last_handshake}}
• Трафик: {{transfer}}{{time_remaining}}
```

### stat_time_remaining
**Purpose**: Remaining test time for basic users

**Variables**:
- `{{hours}}` - Hours remaining

**Example**: `\n• Осталось времени: {{hours}} ч.`

### stat_no_config
**Purpose**: Message when user has no configuration

**Variables**: None

**Example**: `❌ У вас нет активной конфигурации. Создайте подключение через /create`

### stat_error
**Purpose**: Error message when stats cannot be retrieved

**Variables**: None

**Example**: `❌ Не удалось получить статистику. Повторите попытку позже.`

### stat_status_active
**Purpose**: Active connection status text

**Variables**: None

**Example**: `🟢 Активно`

### stat_status_inactive
**Purpose**: Inactive connection status text

**Variables**: None

**Example**: `🔴 Не активно`

### stat_status_never_connected
**Purpose**: Never connected status text

**Variables**: None

**Example**: `⚪ Никогда не подключался`

---

## Delete Command Templates

### delete_no_config
**Purpose**: Message when user tries to delete non-existent config

**Variables**: None

**Example**: `❌ У вас нет активной конфигурации для удаления.`

### delete_confirmation
**Purpose**: Deletion confirmation request

**Variables**:
- `{{status}}` - Current connection status
- `{{last_handshake}}` - Time since last handshake
- `{{transfer}}` - Transfer statistics

**Example**:
```
⚠️ Вы уверены, что хотите удалить конфигурацию?

Текущий статус:
• Статус: {{status}}
• Последний handshake: {{last_handshake}}
• Трафик: {{transfer}}

Это действие необратимо!
```

### delete_success
**Purpose**: Successful deletion message

**Variables**: None

**Example**: `✅ Конфигурация успешно удалена.`

### delete_error
**Purpose**: Deletion error message

**Variables**: None

**Example**: `❌ Ошибка при удалении конфигурации. Попробуйте позже.`

### delete_cancelled
**Purpose**: Message when deletion is cancelled

**Variables**: None

**Example**: `✅ Удаление отменено. Конфигурация сохранена.`

---

## Premium Status Templates

### premium_status_none
**Purpose**: Message for users without premium

**Variables**: None

**Example**:
```
ℹ️ У вас нет активной премиум-подписки.

Премиум-статус предоставляет:
• Неограниченное время использования
• Отсутствие автоудаления
• Приоритетную поддержку

Для оформления свяжитесь с администратором.
```

### premium_status_active
**Purpose**: Message for users with active premium

**Variables**:
- `{{expiration_date}}` - Expiration date or "Бессрочно"

**Example**:
```
✅ У вас активная премиум-подписка!

Действует до: {{expiration_date}}

Преимущества вашего статуса:
• Неограниченное время использования
• Отсутствие автоудаления
• Приоритетная поддержка
```

### premium_status_expired
**Purpose**: Message for users with expired premium

**Variables**:
- `{{expiration_date}}` - Expiration date

**Example**:
```
⏱️ Ваша премиум-подписка истекла {{expiration_date}}.

Для продления свяжитесь с администратором.

Сейчас применяются ограничения бесплатного аккаунта.
```

---

## Help and Info Templates

### help_text
**Purpose**: Help message with bot usage instructions

**Variables**:
- `{{bot_name}}` - Name of the bot

**Example**:
```
📖 Справка по использованию {{bot_name}}

Основные команды:
/create - Создать VPN-подключение
/stat - Статистика подключения
/delete - Удалить конфигурацию
/info - Информация о сервисе
/premium - Информация о премиум-статусе
/feedback - Отправить обратную связь

После создания конфигурации выполните полученную команду на вашем роутере Keenetic.
```

### info_text
**Purpose**: Information about the VPN service

**Variables**:
- `{{bot_name}}` - Name of the bot

**Example**:
```
ℹ️ О сервисе {{bot_name}}

Этот бот автоматизирует создание WireGuard VPN-конфигураций для роутеров Keenetic и некоторых устройств OpenWRT.

Особенности:
• Автоматическая настройка
• Защищённое соединение
• Поддержка IPv4 и IPv6
• Опциональная обфускация

Для получения помощи используйте /help
```

### selfhost_info
**Purpose**: Self-hosting instructions

**Variables**:
- `{{bot_name}}` - Name of the bot

**Example**:
```
🛠️ Self-hosting {{bot_name}}

Вы можете развернуть собственный экземпляр бота.

Инструкции доступны в репозитории:
https://github.com/your-repo/phobos-bot

Требования:
• VPS с WireGuard
• Go 1.21+
• SQLite 3

Подробная документация в README.md
```

---

## Feedback Templates

### feedback_request
**Purpose**: Request for feedback message

**Variables**: None

**Example**:
```
💬 Отправка обратной связи

Напишите ваше сообщение в следующем сообщении.

Мы рассмотрим его и ответим в ближайшее время.
```

### feedback_received
**Purpose**: Confirmation that feedback was received

**Variables**: None

**Example**:
```
✅ Спасибо за обратную связь!

Ваше сообщение получено и будет рассмотрено администратором.
```

### feedback_error
**Purpose**: Error saving feedback

**Variables**: None

**Example**: `❌ Ошибка при сохранении сообщения. Попробуйте позже.`

---

## UI Elements

### button_yes
**Purpose**: "Yes" button text

**Variables**: None

**Example**: `Да`

### button_no
**Purpose**: "No" button text

**Variables**: None

**Example**: `Нет`

---

## System Messages

### blocked_user
**Purpose**: Message shown to blocked users

**Variables**: None

**Example**: `🚫 Бот временно недоступен для Вашего аккаунта.`

### unknown_command
**Purpose**: Message for unrecognized commands

**Variables**: None

**Example**: `❓ Неизвестная команда. Используйте /help для просмотра доступных команд.`

### callback_create
**Purpose**: Callback response for create button

**Variables**: None

**Example**: `Используйте команду /create для создания подключения.`

---

## Variable Substitution

Variables are substituted using the following format:

```go
templateText := "Hello, {{username}}!"
variables := map[string]interface{}{
    "username": "John",
}
result := substituteVariables(templateText, variables)
// Result: "Hello, John!"
```

### Implementation

The `DatabaseMessageManager.GetMessage()` method handles substitution:

```go
func (dmm *DatabaseMessageManager) GetMessage(name string, data map[string]interface{}) (string, error) {
    template, err := dmm.TemplateRepo.GetMessage(name)
    if err != nil {
        return "", err
    }

    result := template.TemplateText
    for key, value := range data {
        placeholder := fmt.Sprintf("{{%s}}", key)
        strValue := fmt.Sprintf("%v", value)
        result = strings.ReplaceAll(result, placeholder, strValue)
    }

    return result, nil
}
```

---

## Best Practices

1. **Naming Convention**: Use descriptive snake_case names: `command_name_action`
2. **Variable Names**: Use lowercase with underscores: `{{user_name}}`, `{{expiration_date}}`
3. **Consistency**: Use same variable names across related templates
4. **Validation**: Always provide fallback values when variables might be missing
5. **Localization**: Use `language_code` for multi-language support
6. **Version Control**: Increment `version` when making significant changes

---

## Adding New Templates

To add a new template:

1. Insert into `message_templates` table:
```sql
INSERT INTO message_templates (message_key, template_text, language_code, version)
VALUES ('new_template_key', 'Template text with {{variable}}', 'ru', 1);
```

2. Use in code:
```go
message, _ := h.messageManager.GetMessage("new_template_key", map[string]interface{}{
    "variable": "value",
})
```

3. Document in this file with purpose, variables, and example

---

## Future Enhancements

- [ ] Multi-language support (en, uk, etc.)
- [ ] Rich formatting (Markdown/HTML)
- [ ] Template validation on save
- [ ] Variable type checking
- [ ] Admin UI for template management
- [ ] Template versioning system
- [ ] A/B testing support
