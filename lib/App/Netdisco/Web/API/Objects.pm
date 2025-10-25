package App::Netdisco::Web::API::Objects;

# 对象API模块
# 提供网络对象数据访问API功能

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Swagger;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::JobQueue 'jq_insert';
use Try::Tiny;

# 设备对象API路由
# 返回设备表中的一行数据
swagger_path {
  tags        => ['Objects'],
  path        => (setting('api_base') || '') . '/object/device/{ip}',
  description => 'Returns a row from the device table',
  parameters  => [
    ip => {description => 'Canonical IP of the Device. Use Search methods to find this.', required => 1, in => 'path',},
  ],
  responses => {default => {}},
  },
  get '/api/v1/object/device/:ip' => require_role api => sub {

  # 查找设备记录
  my $device = try {
    schema(vars->{'tenant'})->resultset('Device')->find(params->{ip})
  } or send_error('Bad Device', 404);
  return to_json $device->TO_JSON;
  };

# 设备关联对象API路由
# 为给定设备返回关联对象行数据
foreach my $rel (qw/device_ips vlans ports modules port_vlans wireless_ports ssids powered_ports/) {
  swagger_path {
    tags        => ['Objects'],
    path        => (setting('api_base') || '') . "/object/device/{ip}/$rel",
    description => "Returns $rel rows for a given device",
    parameters  => [
      ip =>
        {description => 'Canonical IP of the Device. Use Search methods to find this.', required => 1, in => 'path',},
    ],
    responses => {default => {}},
    },
    get "/api/v1/object/device/:ip/$rel" => require_role api => sub {

    # 获取设备关联对象
    my $rows = try {
      schema(vars->{'tenant'})->resultset('Device')->find(params->{ip})->$rel
    } or send_error('Bad Device', 404);
    return to_json [map { $_->TO_JSON } $rows->all];
    };
}

# 设备邻居API路由
# 返回给定设备的第2层邻居关系数据
swagger_path {
  tags        => ['Objects'],
  path        => setting('api_base') . "/object/device/{ip}/neighbors",
  description => 'Returns layer 2 neighbor relation data for a given device',
  parameters  => [
    ip => {description => 'Canonical IP of the Device. Use Search methods to find this.', required => 1, in => 'path',},
    scope => {
      description => 'Scope of results, either "all", "cloud" (LLDP cloud), or "depth" (uses hops)',
      default     => 'depth',
      in          => 'query',
    },
    hops =>
      {description => 'When specifying Scope "depth", this is the number of hops', default => '1', in => 'query',},
    vlan => {description => 'Limit results to devices carrying this numeric VLAN ID',},
  ],
  responses => {default => {}},
  },
  get "/api/v1/object/device/:ip/neighbors" => require_role api => sub {

  # 转发到网络地图数据处理器
  forward "/ajax/data/device/netmap", {q => params->{'ip'}, depth => params->{'hops'}, mapshow => params->{'scope'},};
  };

# 设备作业删除API路由
# 删除设备作业并清除跳过列表，可选择字段过滤
swagger_path {
  tags        => ['Objects'],
  path        => (setting('api_base') || '') . '/object/device/{ip}/jobs',
  description => 'Delete jobs and clear skiplist for a device, optionally filtered by fields',
  parameters  => [
    ip => {description => 'Canonical IP of the Device. Use Search methods to find this.', required => 1, in => 'path',},
    port     => {description => 'Port field of the Job',},
    action   => {description => 'Action field of the Job',},
    status   => {description => 'Status field of the Job',},
    username => {description => 'Username of the Job submitter',},
    userip   => {description => 'IP address of the Job submitter',},
    backend  => {description => 'Backend instance assigned the Job',},
  ],
  responses => {default => {}},
  },
  del '/api/v1/object/device/:ip/jobs' => require_role api_admin => sub {

  # 验证设备存在
  my $device = try {
    schema(vars->{'tenant'})->resultset('Device')->find(params->{ip})
  } or send_error('Bad Device', 404);

  # 删除匹配的作业
  my $gone = schema(vars->{'tenant'})->resultset('Admin')->search({
    device => param('ip'),
    (param('port')   ? (port   => param('port'))   : ()), (param('action')   ? (action   => param('action'))   : ()),
    (param('status') ? (status => param('status')) : ()), (param('username') ? (username => param('username')) : ()),
    (param('userip') ? (userip => param('userip')) : ()), (param('backend')  ? (backend  => param('backend'))  : ()),
  })->delete;

  # 删除匹配的跳过列表条目
  schema(vars->{'tenant'})->resultset('DeviceSkip')->search({
    device => param('ip'),
    (param('action')  ? (actionset => {'&&' => \['ARRAY[?]', param('action')]}) : ()),
    (param('backend') ? (backend   => param('backend'))                         : ()),
  })->delete;

  return to_json {deleted => ($gone || 0)};
  };

# 端口关联对象API路由
# 为给定端口返回关联对象行数据
foreach my $rel (qw/nodes active_nodes nodes_with_age active_nodes_with_age port_vlans vlans logs/) {
  swagger_path {
    tags        => ['Objects'],
    description => "Returns $rel rows for a given port",
    path        => (setting('api_base') || '') . "/object/device/{ip}/port/{port}/$rel",
    parameters  => [
      ip =>
        {description => 'Canonical IP of the Device. Use Search methods to find this.', required => 1, in => 'path',},
      port => {
        description => 'Name of the port. Use the ".../device/{ip}/ports" method to find these.',
        required    => 1,
        in          => 'path',
      },
    ],
    responses => {default => {}},
    },
    get qr{/api/v1/object/device/(?<ip>[^/]+)/port/(?<port>.+)/${rel}$} => require_role api => sub {
    my $params = captures;

    # 获取端口关联对象
    my $rows = try {
      schema(vars->{'tenant'})->resultset('DevicePort')->find($$params{port}, $$params{ip})->$rel
    } or send_error('Bad Device or Port', 404);
    return to_json [map { $_->TO_JSON } $rows->all];
    };
}

# 端口关联表条目API路由
# 为给定端口返回关联表条目
foreach my $rel (qw/power properties ssid wireless agg_master neighbor last_node/) {
  swagger_path {
    tags        => ['Objects'],
    description => "Returns the related $rel table entry for a given port",
    path        => (setting('api_base') || '') . "/object/device/{ip}/port/{port}/$rel",
    parameters  => [
      ip =>
        {description => 'Canonical IP of the Device. Use Search methods to find this.', required => 1, in => 'path',},
      port => {
        description => 'Name of the port. Use the ".../device/{ip}/ports" method to find these.',
        required    => 1,
        in          => 'path',
      },
    ],
    responses => {default => {}},
    },
    get qr{/api/v1/object/device/(?<ip>[^/]+)/port/(?<port>.+)/${rel}$} => require_role api => sub {
    my $params = captures;

    # 获取端口关联表条目
    my $row = try {
      schema(vars->{'tenant'})->resultset('DevicePort')->find($$params{port}, $$params{ip})->$rel
    } or send_error('Bad Device or Port', 404);
    return to_json $row->TO_JSON;
    };
}

# 端口对象API路由
# 必须在端口方法之后，以便路由匹配
swagger_path {
  tags        => ['Objects'],
  description => 'Returns a row from the device_port table',
  path        => (setting('api_base') || '') . '/object/device/{ip}/port/{port}',
  parameters  => [
    ip => {description => 'Canonical IP of the Device. Use Search methods to find this.', required => 1, in => 'path',},
    port => {
      description => 'Name of the port. Use the ".../device/{ip}/ports" method to find these.',
      required    => 1,
      in          => 'path',
    },
  ],
  responses => {default => {}},
  },
  get qr{/api/v1/object/device/(?<ip>[^/]+)/port/(?<port>.+)$} => require_role api => sub {
  my $params = captures;

  # 获取端口对象
  my $port = try {
    schema(vars->{'tenant'})->resultset('DevicePort')->find($$params{port}, $$params{ip})
  } or send_error('Bad Device or Port', 404);
  return to_json $port->TO_JSON;
  };

# 设备节点API路由
# 返回在给定设备上发现的节点
swagger_path {
  tags        => ['Objects'],
  path        => (setting('api_base') || '') . '/object/device/{ip}/nodes',
  description => "Returns the nodes found on a given Device",
  parameters  => [
    ip => {description => 'Canonical IP of the Device. Use Search methods to find this.', required => 1, in => 'path',},
    active_only =>
      {description => 'Restrict results to active Nodes only', type => 'boolean', default => 'true', in => 'query',},
  ],
  responses => {default => {}},
  },
  get '/api/v1/object/device/:ip/nodes' => require_role api => sub {

  # 检查是否只返回活跃节点
  my $active = (params->{active_only} and ('true' eq params->{active_only})) ? 1 : 0;

  # 搜索设备节点
  my $rows = try {
    schema(vars->{'tenant'})->resultset('Node')->search({switch => params->{ip}, ($active ? (-bool => 'active') : ())})
  } or send_error('Bad Device', 404);
  return to_json [map { $_->TO_JSON } $rows->all];
  };

# 设备节点作业API路由
# 将作业加入队列以存储在给定设备上发现的节点
swagger_path {
  tags        => ['Objects'],
  path        => (setting('api_base') || '') . '/object/device/{ip}/nodes',
  description => "Queue a job to store the nodes found on a given Device",
  parameters  => [
    ip => {description => 'Canonical IP of the Device. Use Search methods to find this.', required => 1, in => 'path',},
    nodes => {
      description => 'List of node tuples (port, VLAN, MAC)',
      default     => '[]',
      schema      => {
        type  => 'array',
        items => {
          type       => 'object',
          properties =>
            {port => {type => 'string'}, vlan => {type => 'integer', default => '1'}, mac => {type => 'string'}}
        }
      },
      in => 'body',
    },
  ],
  responses => {default => {}},
  },
  put '/api/v1/object/device/:ip/nodes' => require_role setting('defanged_api_admin') => sub {

  # 插入MAC收集作业
  jq_insert([{
    action    => 'macsuck',
    device    => params->{ip},
    subaction => request->body,
    username  => session('logged_in_user'),
    userip    => request->remote_address,
  }]);

  return to_json {};
  };

# VLAN节点API路由
# 返回在给定VLAN中发现的节点
swagger_path {
  tags        => ['Objects'],
  path        => (setting('api_base') || '') . '/object/vlan/{vlan}/nodes',
  description => "Returns the nodes found in a given VLAN",
  parameters  => [
    vlan        => {description => 'VLAN number', type => 'integer', required => 1, in => 'path',},
    active_only =>
      {description => 'Restrict results to active Nodes only', type => 'boolean', default => 'true', in => 'query',},
  ],
  responses => {default => {}},
  },
  get '/api/v1/object/vlan/:vlan/nodes' => require_role api => sub {

  # 检查是否只返回活跃节点
  my $active = (params->{active_only} and ('true' eq params->{active_only})) ? 1 : 0;

  # 搜索VLAN节点
  my $rows = try {
    schema(vars->{'tenant'})->resultset('Node')->search({vlan => params->{vlan}, ($active ? (-bool => 'active') : ())})
  } or send_error('Bad VLAN', 404);
  return to_json [map { $_->TO_JSON } $rows->all];
  };

# 设备ARP作业API路由
# 将作业加入队列以存储在给定设备上发现的ARP条目
swagger_path {
  tags        => ['Objects'],
  path        => (setting('api_base') || '') . '/object/device/{ip}/arps',
  description => "Queue a job to store the ARP entries found on a given Device",
  parameters  => [
    ip => {description => 'Canonical IP of the Device. Use Search methods to find this.', required => 1, in => 'path',},
    arps => {
      description => 'List of arp tuples (MAC, IP, DNS?). IPs will be resolved to FQDN by Netdisco.',
      default     => '[]',
      schema      => {
        type  => 'array',
        items => {
          type       => 'object',
          properties => {
            mac => {type => 'string', required => 1,},
            ip  => {type => 'string', required => 1,},
            dns => {type => 'string', required => 0,}
          }
        }
      },
      in => 'body',
    },
  ],
  responses => {default => {}},
  },
  put '/api/v1/object/device/:ip/arps' => require_role setting('defanged_api_admin') => sub {

  # 插入ARP收集作业
  jq_insert([{
    action    => 'arpnip',
    device    => params->{ip},
    subaction => request->body,
    username  => session('logged_in_user'),
    userip    => request->remote_address,
  }]);

  return to_json {};
  };

true;
