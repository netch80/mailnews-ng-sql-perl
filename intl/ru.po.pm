package mn_ovl_po;

return 1;

sub parameters { return {

'cp_keys' => 'us-ascii',
'cp_values' => 'koi8-r'

} };

sub translations { return {

'%d command(s) recognized' =>
'%d ������ ����������',

'%s (%d groups)' =>
'%s (%d �����)',

'Your subscription' =>
'���� ��������:',

'You are not our client. Functions are partially unavailable' =>
'�� �� ��� ������������ - ����� ������� ����������',

'Group %s: %s' =>
'������ %s: %s',

'Group %s: state is not changed: %s' =>
'������ %s: ��������� �� ��������: %s%s',

'List headers are off' =>
'��������� ������� ���������',

'Top-level hierarchies:' =>
'�������� �������� ������:',

'Command "DELETE FROM subs" failed: database failure: %s' =>
'������� DELETE FROM subs �� ���������: ����� ����: %s',

'Command "DELETE FROM users" failed: database failure: %s' =>
'������� DELETE FROM users �� ���������: ����� ����: %s',

'Command succeeded' =>
'������� ���������',

'Command succeeded, %d letters sent with %d records' =>
'������� ���������, ���������� %d ����� � %d ��������',

'Command is unavailable' =>
'������� ���������',

'Command failed' =>
'������� �� ���������',

'Command failed: database failure' =>
'������� �� ���������: ���������� ����',

'Command failed: incorrect parameter' =>
'������� �� ���������: ������������ ��������',

'Command failed: no connect to server' =>
'������� �� ���������: ��� ���������� � ��������',

'Command failed: cannot get article header: %s' =>
'������� �� ���������: ����� ������ ���������: %s',

'Command failed: cannot get article body: %s' =>
'������� �� ���������: ����� ������ ���� ������: %s',

'Command failed: group is unknown: %s' =>
'������� �� ���������: ����� �������� ������: %s',

'Command is syntactically invalid' =>
'������� ������������� �����������',

'Command succeeded' =>
'������� ������� ���������',

'Cannot execute INSERT in database: %s' =>
'�� ���� ��������� ������� INSERT � ����: %s',

'Cannot execute UPDATE in database: %s' =>
'�� ���� ��������� ������� UPDATE � ����',

'Cannot start new letter with index' =>
'�� ���� ������ ����� ������ � ��������',

'Cannot prepare INSERT: %s' =>
'�� ���� ����������� INSERT: %s',

'Cannot prepare UPDATE: %s' =>
'�� ���� ����������� UPDATE: %s',

'Cannot prepare command' =>
'�� ���� ����������� �������',

'Cannot get data from database' =>
'�� ���� �������� ������ �� ����',

'Cannot get groups list' =>
'�� ���� �������� ������ �����������',

'Cannot connect to server' =>
'�� ���� ����������� � ��������',

'Invalid group. Group selection dropped.' =>
'������������ ������. ����� ������ �������.',

'No connection to database: %s. Command failed' =>
'��� ����� � �����: %s. ������� �� ���������',

'No connection to database: %s. Command failed.' =>
'��� ����� � �����: %s. ������� �� ���������.',

'No group selected. Command failed' =>
'��� ������� ������. ������� �� ���������',

'No command was recognized.' =>
'�� ����� ������� �� ����������.',

'Subscription resumed' =>
'�������� ������������',

'Subscription of the whole domain suspended' =>
'�������� ����� ������ ��������������',

'' =>
'�������� �� %s �� ��������� �� �������: %s',

'' =>
'�������� ��������������',

'' =>
'��������� �������� ����������',

'' =>
'��������� ������� � ������� �� <%s>',

'' =>
'������� ������ �� �������',

'' =>
'���������: %s',

'' => ''

} }

sub texts { return {

'lhelp' =>
"#    ��� ����, ����� �������� ��������� �� ���� ������������� ������,\n".
"#   ������� ���� '-' �� ������ ������� ��������������� ����� � ���������\n".
"#   ������ ����� �� \${mn_config::cf_server_email}. ��� ��������������\n".
"#   ���������� � ���� ������� ����� �������. ������� ����� ������ �������\n".
"# GROUP ���������������\n".
"# ART �����\n".
"#   ������ �� ����� ��������� ��� ��������, � ����� ������� GROUP �\n".
"#   ������� �����, �� ������� �� ������ �� ����������, ����� ����� �������.\n"

} }
