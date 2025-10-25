package App::Netdisco::Web::API::Queue;

# 队列API模块
# 提供作业队列管理API功能

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Swagger;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::JobQueue 'jq_insert';
use Try::Tiny;

# 后端列表API路由
# 返回当前活跃的后端名称列表（通常是FQDN）
swagger_path {
  tags => ['Queue'],
  path => (setting('api_base') || '').'/queue/backends',
  description => 'Return list of currently active backend names (usually FQDN)',
  responses => { default => {} },
}, get '/api/v1/queue/backends' => require_role api_admin => sub {
  # 从1d988bbf7开始，这总是返回一个条目
  my @names = schema(vars->{'tenant'})->resultset('DeviceSkip')
    ->get_distinct_col('backend');

  return to_json \@names;
};

# 作业列表API路由
# 返回队列中的作业，可选择字段过滤
swagger_path {
  tags => ['Queue'],
  path => (setting('api_base') || '').'/queue/jobs',
  description => 'Return jobs in the queue, optionally filtered by fields',
  parameters  => [
    limit => {
      description => 'Maximum number of Jobs to return',
      type => 'integer',
      default => (setting('jobs_qdepth') || 50),
    },
    device => {
      description => 'IP address field of the Job',
    },
    port => {
      description => 'Port field of the Job',
    },
    action => {
      description => 'Action field of the Job',
    },
    status => {
      description => 'Status field of the Job',
    },
    username => {
      description => 'Username of the Job submitter',
    },
    userip => {
      description => 'IP address of the Job submitter',
    },
    backend => {
      description => 'Backend instance assigned the Job',
    },
  ],
  responses => { default => {} },
}, get '/api/v1/queue/jobs' => require_role api_admin => sub {
  # 搜索作业，应用过滤条件
  my @set = schema(vars->{'tenant'})->resultset('Admin')->search({
    ( param('device')   ? ( device   => param('device') )   : () ),
    ( param('port')     ? ( port     => param('port') )     : () ),
    ( param('action')   ? ( action   => param('action') )   : () ),
    ( param('status')   ? ( status   => param('status') )   : () ),
    ( param('username') ? ( username => param('username') ) : () ),
    ( param('userip')   ? ( userip   => param('userip') )   : () ),
    ( param('backend')  ? ( backend  => param('backend') )  : () ),
    # 排除重复作业
    -or => [
      { 'log' => undef },
      { 'log' => { '-not_like' => 'duplicate of %' } },
    ],
  }, {
    order_by => { -desc => [qw/entered device action/] },
    rows     => (param('limit') || setting('jobs_qdepth') || 50),
  })->with_times->hri->all;

  return to_json \@set;
};

# 作业删除API路由
# 删除作业和跳过列表条目，可选择字段过滤
swagger_path {
  tags => ['Queue'],
  path => (setting('api_base') || '').'/queue/jobs',
  description => 'Delete jobs and skiplist entries, optionally filtered by fields',
  parameters  => [
    device => {
      description => 'IP address field of the Job',
    },
    port => {
      description => 'Port field of the Job',
    },
    action => {
      description => 'Action field of the Job',
    },
    status => {
      description => 'Status field of the Job',
    },
    username => {
      description => 'Username of the Job submitter',
    },
    userip => {
      description => 'IP address of the Job submitter',
    },
    backend => {
      description => 'Backend instance assigned the Job',
    },
  ],
  responses => { default => {} },
}, del '/api/v1/queue/jobs' => require_role api_admin => sub {
  # 删除匹配的作业
  my $gone = schema(vars->{'tenant'})->resultset('Admin')->search({
    ( param('device')   ? ( device   => param('device') )   : () ),
    ( param('port')     ? ( port     => param('port') )     : () ),
    ( param('action')   ? ( action   => param('action') )   : () ),
    ( param('status')   ? ( status   => param('status') )   : () ),
    ( param('username') ? ( username => param('username') ) : () ),
    ( param('userip')   ? ( userip   => param('userip') )   : () ),
    ( param('backend')  ? ( backend  => param('backend') )  : () ),
  })->delete;

  # 删除匹配的跳过列表条目
  schema(vars->{'tenant'})->resultset('DeviceSkip')->search({
    ( param('device')  ? ( device    => param('device') )  : () ),
    ( param('action')  ? ( actionset => { '&&' => \[ 'ARRAY[?]', param('action') ] } ) : () ),
    ( param('backend') ? ( backend   => param('backend') ) : () ),
  })->delete;

  return to_json { deleted => ($gone || 0)};
};

# 作业提交API路由
# 将作业提交到队列
swagger_path {
  tags => ['Queue'],
  path => (setting('api_base') || '').'/queue/jobs',
  description => 'Submit jobs to the queue',
  parameters  => [
    jobs => {
      description => 'List of job specifications (action, device?, port?, extra?).',
      default => '[]',
      schema => {
        type => 'array',
        items => {
          type => 'object',
          properties => {
            action => {
              type => 'string',
              required => 1,
            },
            device => {
              type => 'string',
              required => 0,
            },
            port => {
              type => 'string',
              required => 0,
            },
            extra => {
              type => 'string',
              required => 0,
            }
          }
        }
      },
      in => 'body',
    },
  ],
  responses => { default => {} },
}, post '/api/v1/queue/jobs' => require_any_role [qw(api_admin port_control)] => sub {
  my $data = request->body || '';
  my $jobs = (length $data ? try { from_json($data) } : []);

  send_error('Malformed body', 400) if ref $jobs ne ref [];

  # 验证每个作业
  foreach my $job (@$jobs) {
      send_error('Malformed job', 400) if ref $job ne ref {};
      send_error('Malformed job', 400) if !defined $job->{action};
      # 检查权限
      send_error('Not Authorized', 403)
        # TODO 使其了解每个设备/端口的端口控制角色
        if ($job->{action} =~ m/^cf_/ and not user_has_role('port_control'))
        or ($job->{action} !~ m/^cf_/ and not user_has_role('api_admin'));

      # 添加用户信息
      $job->{username} = session('logged_in_user');
      $job->{userip}   = request->remote_address;
  }

  # 插入作业到队列
  my $happy = jq_insert($jobs);

  return to_json { success => $happy };
};

true;
