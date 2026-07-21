// ==UserScript==
// @name         Cpolar 隧道状态同步
// @namespace    https://github.com/xxx/cpolar-sync
// @version      1.1.0
// @description  自动监控 Cpolar 在线隧道状态，变更时通过钉钉 Webhook 推送通知
// @author       cpolar-sync
// @match        http://localhost:9200/*
// @grant        GM_setValue
// @grant        GM_getValue
// @grant        GM_xmlhttpRequest
// @grant        GM_addStyle
// @run-at       document-end
// @connect      oapi.dingtalk.com
// @connect      localhost
// @license      MIT
// ==/UserScript==