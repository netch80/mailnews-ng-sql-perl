package mn_ovl_po;

return 1;

sub parameters { return {

'cp_keys' => 'us-ascii',
'cp_values' => 'koi8-r'

} };

sub translations { return {

'%d command(s) recognized' =>
'%d команд распознано',

'%s (%d groups)' =>
'%s (%d групп)',

'Your subscription' =>
'Ваша подписка:',

'You are not our client. Functions are partially unavailable' =>
'Вы не наш пользователь - часть функций недоступна',

'Group %s: %s' =>
'Группа %s: %s',

'Group %s: state is not changed: %s' =>
'Группа %s: состояние не меняется: %s%s',

'List headers are off' =>
'Заголовки списков выключены',

'Top-level hierarchies:' =>
'Иерархии верхнего уровня:',

'Command "DELETE FROM subs" failed: database failure: %s' =>
'Команда DELETE FROM subs не выполнена: отказ базы: %s',

'Command "DELETE FROM users" failed: database failure: %s' =>
'Команда DELETE FROM users не выполнена: отказ базы: %s',

'Command succeeded' =>
'Команда выполнена',

'Command succeeded, %d letters sent with %d records' =>
'Команда выполнена, отправлено %d писем с %d записями',

'Command is unavailable' =>
'Команда запрещена',

'Command failed' =>
'Команда не выполнена',

'Command failed: database failure' =>
'Команда не выполнена: возражение базы',

'Command failed: incorrect parameter' =>
'Команда не выполнена: некорректный параметр',

'Command failed: no connect to server' =>
'Команда не выполнена: нет соединения с сервером',

'Command failed: cannot get article header: %s' =>
'Команда не выполнена: отказ отдать заголовок: %s',

'Command failed: cannot get article body: %s' =>
'Команда не выполнена: отказ отдать тело статьи: %s',

'Command failed: group is unknown: %s' =>
'Команда не выполнена: отказ признать группу: %s',

'Command is syntactically invalid' =>
'Команда синтаксически неправильна',

'Command succeeded' =>
'Команда успешно выполнена',

'Cannot execute INSERT in database: %s' =>
'Не могу выполнить команду INSERT в базе: %s',

'Cannot execute UPDATE in database: %s' =>
'Не могу выполнить команду UPDATE в базе',

'Cannot start new letter with index' =>
'Не могу начать новое письмо с индексом',

'Cannot prepare INSERT: %s' =>
'Не могу подготовить INSERT: %s',

'Cannot prepare UPDATE: %s' =>
'Не могу подготовить UPDATE: %s',

'Cannot prepare command' =>
'Не могу подготовить команду',

'Cannot get data from database' =>
'Не могу получить данные из базы',

'Cannot get groups list' =>
'Не могу получить список конференций',

'Cannot connect to server' =>
'Не могу соединиться с сервером',

'Invalid group. Group selection dropped.' =>
'Недопустимая группа. Выбор группы сброшен.',

'No connection to database: %s. Command failed' =>
'Нет связи с базой: %s. Команда не выполнена',

'No connection to database: %s. Command failed.' =>
'Нет связи с базой: %s. Команда не выполнена.',

'No group selected. Command failed' =>
'Нет текущей группы. Команда не выполнена',

'No command was recognized.' =>
'Ни одной команды не распознано.',

'Subscription resumed' =>
'Подписка возобновлена',

'Subscription of the whole domain suspended' =>
'Подписка всего домена приостановлена',

'' =>
'Подписка на %s не выполнена по причине: %s',

'' =>
'Подписка приостановлена',

'' =>
'Подсказка временно недоступна',

'' =>
'Результат запроса к серверу от <%s>',

'' =>
'Текущая группа не выбрана',

'' =>
'Удаляется: %s',

'' => ''

} }

sub texts { return {

'lhelp' =>
"#    Для того, чтобы заказать некоторые из ниже перечисленных статей,\n".
"#   удалите знак '-' из первой колонки соответствующих строк и отправьте\n".
"#   список назад на \${mn_config::cf_server_email}. Всю дополнительную\n".
"#   информацию в этих строках лучше удалить. Серверу нужны только команды\n".
"# GROUP телеконференция\n".
"# ART номер\n".
"#   Строки со всеми ненужными Вам статьями, а также команды GROUP с\n".
"#   именами групп, из которых Вы ничего не заказывали, также лучше удалить.\n"

} }
