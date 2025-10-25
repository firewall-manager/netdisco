package App::Netdisco::Web::Static;

# 静态资源Web模块
# 提供插件静态资源服务功能

use Dancer ':syntax';
use Path::Class;

# JavaScript插件资源路由
# 提供插件JavaScript文件服务
get '/plugin/*/*.js' => sub {
  my ($plugin) = splat;

  # 使用插件模板生成内容
  my $content = template
    'plugin.tt', { target => "plugin/$plugin/$plugin.js" },
    { layout => undef };

  # 发送JavaScript文件
  send_file \$content,
    content_type => 'application/javascript',
    filename => "$plugin.js";
};

# CSS插件资源路由
# 提供插件CSS文件服务
get '/plugin/*/*.css' => sub {
  my ($plugin) = splat;

  # 使用插件模板生成内容
  my $content = template
    'plugin.tt', { target => "plugin/$plugin/$plugin.css" },
    { layout => undef };

  # 发送CSS文件
  send_file \$content,
    content_type => 'text/css',
    filename => "$plugin.css";
};

true;
