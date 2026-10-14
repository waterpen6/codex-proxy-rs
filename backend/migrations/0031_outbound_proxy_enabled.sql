-- 命名代理独立启停，保留连接配置和账号绑定
alter table outbound_proxies add column enabled boolean not null default true;
