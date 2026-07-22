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

;(function () {
  'use strict'

  // ================================================================
  // 1. 常量与默认配置
  // ================================================================

  /** 脚本版本号，用于后续配置迁移判断 */
  const SCRIPT_VERSION = '1.1.0'
  /** GM_setValue/GM_getValue 存储键名：用户配置 */
  const CONFIG_KEY = 'cpolar_sync_config'
  /** GM_setValue/GM_getValue 存储键名：上次缓存的隧道数据 */
  const CACHE_KEY = 'cpolar_sync_tunnel_cache'
  /** GM_setValue/GM_getValue 存储键名：上次成功推送的隧道数据快照 */
  const LAST_SENT_KEY = 'cpolar_sync_last_sent'
  /** GM_setValue/GM_getValue 存储键名：上次检测/推送状态数据 */
  const STATUS_KEY = 'cpolar_sync_status'

  /**
   * 默认配置项
   * 用户配置中缺失的字段由此补全，保证升级时新增字段有合理默认值
   */
  const DEFAULTS = {
    /** 钉钉 Webhook URL，用户需在机器人设置中获取 */
    webhookUrl: '',
    /** 定时刷新间隔，单位分钟，最小 5 分钟 */
    interval: 5,
    /** 已勾选的隧道名称列表，用于过滤需要监控的隧道 */
    selectedTunnels: [],
    /** 是否启用定时轮询 */
    enabled: false,
    /** 脚本版本，用于检测是否需要迁移配置结构 */
    version: SCRIPT_VERSION,
    /** 调试日志开关，开启后 console 输出详细诊断信息 */
    debug: false
  }

  /**
   * 表格表头关键字映射
   * 键为期望的字段名，值为该字段在表头中可能出现的中英文关键字列表
   * 用于自动识别隧道列表表格中各列的对应关系
   */
  const HEADER_KEYWORDS = {
    name: ['隧道名称', '名称', 'tunnel', 'name', '服务名', '服务名称'],
    protocol: ['协议', 'protocol', '类型', 'type', '传输协议'],
    publicUrl: ['公网地址', '公网', 'public', 'url', '地址', '外网地址', '外网'],
    localAddr: ['本地地址', '本地', 'local', '内网地址', '内网', '本地端口'],
    createTime: ['创建时间', '创建', 'create', 'time', '时间', '添加时间'],
    status: ['状态', 'status', '运行状态', '连接状态', '在线状态']
  }

  /** 目标页面路由，仅精确匹配在线状态页面 */
  const TARGET_ROUTE = '#/status/online'

  // ================================================================
  // 2. 存储模块
  // ================================================================

  /**
   * 存储模块
   * 封装 GM_setValue/GM_getValue，提供配置和缓存数据的读写能力
   * 所有持久化操作都通过此模块完成，便于后续替换存储后端
   */
  const Store = {
    /**
     * 读取用户配置，合并缺失的默认字段
     * @returns {Object} 合并默认值后的完整配置对象
     */
    loadConfig: function () {
      /** 从油猴持久化存储中读取原始配置 */
      const raw = GM_getValue(CONFIG_KEY, {})
      /** 用默认值补全缺失的字段，保证升级脚本后不会因缺少字段而报错 */
      const merged = Object.assign({}, DEFAULTS, raw)
      return merged
    },

    /**
     * 保存用户配置到持久化存储
     * @param {Object} config - 完整的配置对象
     */
    saveConfig: function (config) {
      GM_setValue(CONFIG_KEY, config)
    },

    /**
     * 读取上次缓存的隧道数据
     * @returns {Array|null} 隧道数据数组，无缓存时返回 null
     */
    loadCache: function () {
      return GM_getValue(CACHE_KEY, null)
    },

    /**
     * 保存当前隧道数据到缓存
     * @param {Array} data - 隧道数据数组
     */
    saveCache: function (data) {
      GM_setValue(CACHE_KEY, data)
    },

    /**
     * 读取上次成功推送的隧道数据快照
     * @returns {Array|null} 隧道数据数组，无记录时返回 null
     */
    loadLastSent: function () {
      return GM_getValue(LAST_SENT_KEY, null)
    },

    /**
     * 保存本次推送的隧道数据快照
     * @param {Array} data - 推送成功的隧道数据数组
     */
    saveLastSent: function (data) {
      GM_setValue(LAST_SENT_KEY, data)
    },

    /**
     * 读取上次检测/推送状态数据
     * @returns {Object|null}
     */
    loadStatus: function () {
      return GM_getValue(STATUS_KEY, null)
    },

    /**
     * 保存本次检测/推送状态数据
     * @param {Object} data - { lastCheckTime, lastCheckStatus, lastPushTime, nextCheckTime }
     */
    saveStatus: function (data) {
      GM_setValue(STATUS_KEY, data)
    }
  }

  // ================================================================
  // 2.5. 调试日志模块
  // ================================================================

  /**
   * 调试日志模块
   * 所有日志输出均受 Store 中 debug 标志控制，
   * 同时在 window 上暴露 cpolarSyncDebug(bool) 函数用于运行时切换
   * 日志前缀 [CpolarSync] 方便在浏览器控制台中过滤
   */
  const Log = {
    /**
     * 检查当前是否处于调试模式
     * @returns {boolean}
     */
    _isEnabled: function () {
      try {
        var cfg = Store.loadConfig()
        return cfg.debug === true
      } catch (e) {
        return false
      }
    },

    /**
     * 通用日志输出，仅在调试模式开启时打印
     * @param {string} level - 日志级别（log/info/warn/error）
     * @param {string} tag - 模块标签，如 [UI] [Parser] [Sidebar]
     * @param {*} msg - 主消息内容
     * @param {*} extra - 附加数据（可选），会展开打印
     */
    _print: function (level, tag, msg, extra) {
      if (!this._isEnabled()) return
      var prefix = '%c[CpolarSync]' + tag + '%c ' + msg
      var style1 = 'color:#1a7f37;font-weight:bold;'
      var style2 = 'color:inherit;'
      if (extra !== undefined) {
        console[level](prefix, style1, style2, extra)
      } else {
        console[level](prefix, style1, style2)
      }
    },

    /**
     * 输出普通信息日志
     * @param {string} tag - 模块标签
     * @param {string} msg - 消息
     * @param {*} [extra] - 可选附加数据
     */
    log: function (tag, msg, extra) {
      this._print('log', tag, msg, extra)
    },

    /**
     * 输出信息级日志
     * @param {string} tag - 模块标签
     * @param {string} msg - 消息
     * @param {*} [extra] - 可选附加数据
     */
    info: function (tag, msg, extra) {
      this._print('info', tag, msg, extra)
    },

    /**
     * 输出警告日志
     * @param {string} tag - 模块标签
     * @param {string} msg - 消息
     * @param {*} [extra] - 可选附加数据
     */
    warn: function (tag, msg, extra) {
      this._print('warn', tag, msg, extra)
    },

    /**
     * 输出错误日志
     * @param {string} tag - 模块标签
     * @param {string} msg - 消息
     * @param {*} [extra] - 可选附加数据
     */
    error: function (tag, msg, extra) {
      this._print('error', tag, msg, extra)
    },

    /**
     * 输出 DOM 元素的结构快照（标签名、类名、位置、尺寸、子元素数量）
     * @param {string} tag - 模块标签
     * @param {string} label - 该元素的描述文字
     * @param {Element} el - DOM 元素
     */
    dumpElement: function (tag, label, el) {
      if (!this._isEnabled() || !el) return
      var info = {
        tag: el.tagName,
        id: el.id || '(无)',
        className: String(el.className || '').substring(0, 120),
        children: el.children.length,
        rect: el.getBoundingClientRect()
      }
      this._print('log', tag, label, info)
    },

    /**
     * 输出 body / #app 的整体 DOM 结构概览（仅子元素一级）
     */
    dumpPageLayout: function () {
      if (!this._isEnabled()) return
      this._print('log', '[Layout]', '=== 页面布局诊断开始 ===')

      /** body 层 */
      this._print('log', '[Layout]', 'document.body 子元素:')
      Array.from(document.body.children).forEach(function (child, idx) {
        var r = child.getBoundingClientRect()
        this._print('log', '[Layout]', '  [' + idx + '] <' + child.tagName + '> id=' + (child.id || '(无)') + ' class=' + String(child.className || '').substring(0, 60),
          { left: r.left, top: r.top, width: r.width, height: r.height, zIndex: window.getComputedStyle(child).zIndex, position: window.getComputedStyle(child).position })
      }.bind(this))

      /** #app 层 */
      var app = document.querySelector('#app')
      if (app) {
        this._print('log', '[Layout]', '#app 子元素:')
        Array.from(app.children).forEach(function (child, idx) {
          var r = child.getBoundingClientRect()
          this._print('log', '[Layout]', '  [' + idx + '] <' + child.tagName + '> id=' + (child.id || '(无)') + ' class=' + String(child.className || '').substring(0, 60),
            { left: r.left, top: r.top, width: r.width, height: r.height, position: window.getComputedStyle(child).position })
        }.bind(this))
      } else {
        this._print('log', '[Layout]', '页面中不存在 #app 容器')
      }

      this._print('log', '[Layout]', '=== 页面布局诊断结束 ===')
    }
  }

  // ================================================================
  // 3. 页面解析模块
  // ================================================================

  /**
   * 解析模块
   * 负责从 Cpolar 在线状态页面 DOM 中提取隧道列表
   * 采用智能表头匹配策略：遍历页面中所有表格，通过表头文字匹配隧道字段，
   * 选择匹配度最高的表格作为数据源，按列位置提取对应数据
   */
  const Parser = {
    /**
     * 等待页面中的表格元素出现
     * Cpolar 使用 Vue 动态渲染，DOM 可能在 document-end 后仍未完成，
     * 因此需要轮询等待目标表格出现
     * @param {number} timeout - 超时时间（毫秒），默认 15 秒
     * @returns {Promise<boolean>} 超时内是否找到表格
     */
    waitForTable: function (timeout) {
      var _this = this
      return new Promise(function (resolve) {
        /** 轮询间隔，每 500ms 检查一次 */
        var pollInterval = 500
        /** 已等待时间 */
        var elapsed = 0

        var timer = setInterval(function () {
          elapsed += pollInterval

          /** 尝试在当前 DOM 中查找隧道表格 */
          var table = _this._findBestTable()
          if (table) {
            clearInterval(timer)
            resolve(true)
            return
          }

          /** 超时仍未找到表格，不再等待 */
          if (elapsed >= timeout) {
            clearInterval(timer)
            resolve(false)
            return
          }
        }, pollInterval)
      })
    },

    /**
     * 解析页面 DOM，提取所有隧道信息
     * 先尝试智能匹配找到最佳表格，然后提取数据行
     * @returns {Array} 隧道信息数组，每项包含 name/protocol/publicUrl/localAddr/createTime/status
     */
    parseTunnelList: function () {
      /** 找到表头匹配度最高的表格 */
      var table = this._findBestTable()
      if (!table) {
        return []
      }

      /** 获取表格表头行，确定各列对应的字段 */
      var headerCells = this._getHeaderCells(table)
      var columnMap = this._matchColumnMap(headerCells)

      /** 找不到任何匹配的字段列，无法解析 */
      if (Object.keys(columnMap).length === 0) {
        return []
      }

      /**
       * Element UI 的 el-table 将表头和表体拆成两个独立的 <table>：
       *   el-table__header（表头，含 <th>）— _findBestTable 找到的是这个
       *   el-table__body（表体，含 <td>）— 实际数据行在这里
       * 因此需要找到对应的 body table 来提取行数据
       */
      var dataTable = table
      var elTable = table.closest('.el-table')
      if (elTable) {
        var bodyTable = elTable.querySelector('.el-table__body')
        if (bodyTable) {
          dataTable = bodyTable
          Log.log('[Parser]', '使用 el-table__body 提取数据行')
        }
      }

      /** 提取数据行 */
      return this._extractRows(dataTable, columnMap)
    },

    /**
     * 查找页面中表头匹配度最高的表格
     * 遍历页面中所有包含 <th> 的表格，计算表头文本与预定义关键字的匹配分数，
     * 返回分数最高的表格元素
     * @returns {Element|null} 匹配度最高的表格元素，无匹配时返回 null
     */
    _findBestTable: function () {
      /** 页面中所有 table 元素 */
      var tables = document.querySelectorAll('table')
      var bestScore = 0
      var bestTable = null

      tables.forEach(function (table) {
        /** 该表格的字段匹配计数 */
        var score = 0
        /** 表头行中所有 th 元素 */
        var headers = table.querySelectorAll('th')

        headers.forEach(function (th) {
          /** 去除 th 内的换行和多余空白，取纯净的文本内容用于匹配 */
          var text = th.textContent.trim().replace(/\s+/g, '')
          if (!text) return

          /** 遍历每个预定义字段的关键字列表 */
          Object.keys(HEADER_KEYWORDS).forEach(function (field) {
            var keywords = HEADER_KEYWORDS[field]
            /** 只要该字段的任一关键字出现在表头文本中，计 1 分 */
            var matched = keywords.some(function (kw) {
              return text.indexOf(kw) !== -1
            })
            if (matched) {
              score++
            }
          })
        })

        /** 至少匹配 2 个字段才算有效表格，防止误匹配 */
        if (score > bestScore && score >= 2) {
          bestScore = score
          bestTable = table
        }
      })

      return bestTable
    },

    /**
     * 获取表格的表头单元格列表
     * 优先使用 <thead><th>，回退到第一行中的所有 <th> 或 <td>
     * @param {Element} table - 表格元素
     * @returns {Array} 表头文本数组
     */
    _getHeaderCells: function (table) {
      /** 尝试从 <thead> 中获取 th */
      var thead = table.querySelector('thead')
      if (thead) {
        var ths = thead.querySelectorAll('th')
        if (ths.length > 0) {
          return Array.from(ths).map(function (th) {
            return { element: th, text: th.textContent.trim().replace(/\s+/g, '') }
          })
        }
      }

      /** 无 thead 时，取第一行作为表头 */
      var firstRow = table.querySelector('tr')
      if (firstRow) {
        var cells = firstRow.querySelectorAll('th, td')
        return Array.from(cells).map(function (cell) {
          return { element: cell, text: cell.textContent.trim().replace(/\s+/g, '') }
        })
      }

      return []
    },

    /**
     * 将表头文本匹配到预定义字段，返回列索引到字段名的映射
     * 每个字段取匹配分数最高的列，避免一个关键字匹配多列
     * @param {Array} headerCells - 表头单元格文本数组
     * @returns {Object} 字段名到列索引的映射，如 { name: 0, protocol: 1, ... }
     */
    _matchColumnMap: function (headerCells) {
      /** 最终映射结果：字段名 → 列索引 */
      var map = {}

      headerCells.forEach(function (cell, index) {
        if (!cell.text) return

        Object.keys(HEADER_KEYWORDS).forEach(function (field) {
          var keywords = HEADER_KEYWORDS[field]
          /**
           * 检查该列的表头文本是否匹配当前字段的任一关键字
           * 匹配方式：表头文本包含关键字（不区分大小写）
           */
          var matched = keywords.some(function (kw) {
            return cell.text.toLowerCase().indexOf(kw.toLowerCase()) !== -1
          })
          if (matched && !map.hasOwnProperty(field)) {
            /** 每个字段只映射到第一个匹配的列 */
            map[field] = index
          }
        })
      })

      return map
    },

    /**
     * 从表格的数据行中提取隧道信息
     * 跳过表头行（第一行），遍历剩余行，按列映射提取数据
     * @param {Element} table - 表格元素
     * @param {Object} columnMap - 字段名到列索引的映射
     * @returns {Array} 隧道信息数组
     */
    _extractRows: function (table, columnMap) {
      /** 所有数据行（排除在 thead 中的行） */
      var allRows = Array.from(table.querySelectorAll('tr'))
      var dataRows = []

      /**
       * 判断此 table 是否包含表头行：
       * - 有 <thead> 元素
       * - 或者包含 <th> 元素
       * 两者都没有时说明是纯数据表（如 el-table__body），首行不应跳过
       */
      var thead = table.querySelector('thead')
      var hasHeader = thead !== null || table.querySelector('th') !== null

      allRows.forEach(function (row, index) {
        /** 行在 thead 内 → 表头，跳过 */
        if (thead && thead.contains(row)) return
        /** 仅当此 table 包含表头时才跳过第一行 */
        if (hasHeader && index === 0) return
        dataRows.push(row)
      })

      /** 将每行数据转换为 TunnelInfo 对象 */
      return dataRows.map(function (row) {
        var cells = row.querySelectorAll('td')
        var tunnel = {
          name: '',
          protocol: '',
          publicUrl: '',
          localAddr: '',
          createTime: '',
          status: 'online'
        }

        /** 按字段映射提取各列数据 */
        Object.keys(columnMap).forEach(function (field) {
          var colIndex = columnMap[field]
          var cell = cells[colIndex]
          if (cell) {
            /** 取单元格的纯文本内容，去除多余空白 */
            var value = cell.textContent.trim().replace(/\s+/g, ' ')
            /** Element UI 的表格会在 .cell 外有额外空白，取 .cell 内容会更干净 */
            var cellInner = cell.querySelector('.cell')
            if (cellInner) {
              value = cellInner.textContent.trim().replace(/\s+/g, ' ')
            }
            tunnel[field] = value
          }
        })

        /**
         * 判断隧道状态
         * 如果表头中有"状态"列，直接使用该列的值；
         * 否则只要隧道出现在在线页面就认为是 online
         */
        if (columnMap.hasOwnProperty('status')) {
          var statusText = tunnel.status || ''
          /** 包含"离线"/"断开"等字眼判定为离线 */
          var isOffline = statusText.indexOf('离线') !== -1 ||
            statusText.indexOf('断开') !== -1 ||
            statusText.indexOf('offline') !== -1
          tunnel.status = isOffline ? 'offline' : 'online'
        } else {
          /** 出现在在线页面即视为在线 */
          tunnel.status = 'online'
        }

        return tunnel
      }).filter(function (t) {
        /** 过滤掉空行：名称和协议至少有一个值 */
        return t.name || t.protocol || t.publicUrl
      })
    },

    /**
     * 提取隧道唯一标识
     * 使用隧道名称作为标识，当名称可能重复时拼接协议前缀
     * @param {Object} tunnel - 隧道信息对象
     * @returns {string} 唯一标识
     */
    getTunnelId: function (tunnel) {
      if (tunnel.name && tunnel.protocol) {
        return tunnel.name + '|' + tunnel.protocol.toLowerCase()
      }
      return tunnel.name || ''
    }
  }

  // ================================================================
  // 4. 变更检测模块
  // ================================================================

  /**
   * 变更检测模块
   * 对比新旧两批隧道数据，检测新增、更新、移除的隧道
   * 判断变更的标准：任一字段值发生变化即视为更新
   */
  const Diff = {
    /**
     * 检测新旧数据之间的差异
     * 首次运行时（无旧数据）返回全量数据作为新增列表
     * @param {Array} oldData - 上次缓存的隧道数据
     * @param {Array} newData - 当前解析的隧道数据
     * @returns {Object} { added: [], updated: [], removed: [], hasChanges: boolean }
     */
    detect: function (oldData, newData) {
      /** 首次运行：无旧数据，返回全量新增 */
      if (!oldData || !Array.isArray(oldData) || oldData.length === 0) {
        return {
          added: newData,
          updated: [],
          removed: [],
          hasChanges: newData.length > 0
        }
      }

      /** 用 id 索引旧数据，便于快速查找 */
      var oldMap = {}
      oldData.forEach(function (t) {
        var id = Parser.getTunnelId(t)
        oldMap[id] = t
      })

      /** 用 id 索引新数据 */
      var newMap = {}
      newData.forEach(function (t) {
        var id = Parser.getTunnelId(t)
        newMap[id] = t
      })

      var added = []
      var updated = []
      var removed = []

      /** 遍历新数据：检测新增和更新 */
      newData.forEach(function (tunnel) {
        var id = Parser.getTunnelId(tunnel)
        if (!oldMap.hasOwnProperty(id)) {
          /** 旧数据中不存在此隧道 → 新增 */
          added.push(tunnel)
        } else {
          /** 新旧数据不一致 → 更新 */
          if (!this._isEqual(tunnel, oldMap[id])) {
            updated.push(tunnel)
          }
        }
      }, this)

      /** 遍历旧数据：检测移除 */
      oldData.forEach(function (tunnel) {
        var id = Parser.getTunnelId(tunnel)
        if (!newMap.hasOwnProperty(id)) {
          /** 新数据中不存在此隧道 → 标记为离线 */
          tunnel.status = 'offline'
          removed.push(tunnel)
        }
      })

      return {
        added: added,
        updated: updated,
        removed: removed,
        hasChanges: added.length > 0 || updated.length > 0 || removed.length > 0
      }
    },

    /**
     * 比较两个隧道对象是否内容一致
     * 只比较业务字段（name/protocol/publicUrl/localAddr/createTime/status），忽略其他属性
     * @param {Object} a - 隧道 A
     * @param {Object} b - 隧道 B
     * @returns {boolean} 是否完全一致
     */
    _isEqual: function (a, b) {
      /** 需要参与比较的字段列表 */
      var fields = ['name', 'protocol', 'publicUrl', 'localAddr', 'createTime', 'status']
      return fields.every(function (f) {
        return (a[f] || '') === (b[f] || '')
      })
    },

    /**
     * 从全量数据中筛选出用户勾选的隧道
     * @param {Array} allTunnels - 全量隧道列表
     * @param {Array} selectedNames - 用户勾选的隧道名称列表
     * @returns {Array} 勾选的隧道列表
     */
    filterSelected: function (allTunnels, selectedNames) {
      /** 未勾选任何隧道时，默认全选 */
      if (!selectedNames || selectedNames.length === 0) {
        return allTunnels
      }

      return allTunnels.filter(function (t) {
        var id = Parser.getTunnelId(t)
        return selectedNames.indexOf(id) !== -1 || selectedNames.indexOf(t.name) !== -1
      })
    }
  }

  // ================================================================
  // 5. 推送模块（钉钉）
  // ================================================================

  /**
   * 推送模块
   * 构建钉钉 Markdown 消息，通过 GM_xmlhttpRequest 发送 Webhook
   * 支持新增/更新/离线三种变更类型的消息展示
   */
  const Notifier = {
    /**
     * 构建钉钉 Markdown 消息体
     * 根据变更类型生成不同前缀和颜色的消息文本
     * @param {Object} diffResult - 变更检测结果 { added, updated, removed }
     * @returns {Object} 钉钉消息体 { msgtype, markdown: { title, text } }
     */
    buildDingMsg: function (diffResult) {
      /** 当前时间，格式化为可读字符串 */
      var now = new Date()
      var timeStr = now.getFullYear() + '-' +
        String(now.getMonth() + 1).padStart(2, '0') + '-' +
        String(now.getDate()).padStart(2, '0') + ' ' +
        String(now.getHours()).padStart(2, '0') + ':' +
        String(now.getMinutes()).padStart(2, '0') + ':' +
        String(now.getSeconds()).padStart(2, '0')

      /** 构建 Markdown 文本 */
      var lines = []
      lines.push('## Cpolar 隧道状态变更通知')
      lines.push('')
      lines.push('---')
      lines.push('')

      /** 新增隧道 */
      if (diffResult.added.length > 0) {
        diffResult.added.forEach(function (t) {
          lines.push('**🟢 ' + t.name + '** — 新增上线')
          if (t.protocol) lines.push('- 协议：' + t.protocol)
          if (t.publicUrl) lines.push('- 公网地址：' + t.publicUrl)
          if (t.localAddr) lines.push('- 本地地址：' + t.localAddr)
          if (t.createTime) lines.push('- 创建时间：' + t.createTime)
          lines.push('')
        })
      }

      /** 更新隧道 */
      if (diffResult.updated.length > 0) {
        diffResult.updated.forEach(function (t) {
          lines.push('**🔄 ' + t.name + '** — 信息变更')
          if (t.protocol) lines.push('- 协议：' + t.protocol)
          if (t.publicUrl) lines.push('- 公网地址：' + t.publicUrl)
          if (t.localAddr) lines.push('- 本地地址：' + t.localAddr)
          if (t.createTime) lines.push('- 创建时间：' + t.createTime)
          lines.push('')
        })
      }

      /** 离线隧道 */
      if (diffResult.removed.length > 0) {
        diffResult.removed.forEach(function (t) {
          lines.push('**🔴 ' + t.name + '** — 已离线')
          if (t.publicUrl) lines.push('- 原公网地址：' + t.publicUrl)
          if (t.localAddr) lines.push('- 原本地地址：' + t.localAddr)
          lines.push('')
        })
      }

      /** 消息尾部：推送时间 */
      lines.push('---')
      lines.push('')
      lines.push('⏱ 检测时间：' + timeStr)

      return {
        msgtype: 'markdown',
        markdown: {
          title: 'Cpolar 隧道状态变更',
          text: lines.join('\n')
        }
      }
    },

    /**
     * 通过钉钉 Webhook 发送消息
     * 使用 GM_xmlhttpRequest 以绕过浏览器的跨域限制
     * @param {string} webhookUrl - 钉钉机器人 Webhook 地址
     * @param {Object} message - 钉钉消息体对象
     * @returns {Promise} 发送结果，成功返回解析后的响应数据，失败返回错误信息
     */
    sendWebhook: function (webhookUrl, message) {
      /** 校验 webhook 地址不为空 */
      if (!webhookUrl || webhookUrl.trim() === '') {
        return Promise.reject(new Error('Webhook URL 未配置'))
      }

      return new Promise(function (resolve, reject) {
        GM_xmlhttpRequest({
          method: 'POST',
          url: webhookUrl,
          headers: {
            'Content-Type': 'application/json;charset=utf-8'
          },
          data: JSON.stringify(message),
          /**
           * 请求成功回调
           * 钉钉 API 返回 { errcode: 0, errmsg: 'ok' } 表示成功
           */
          onload: function (res) {
            try {
              var result = JSON.parse(res.responseText)
              if (result.errcode === 0) {
                resolve(result)
              } else {
                reject(new Error('钉钉返回错误: ' + (result.errmsg || JSON.stringify(result))))
              }
            } catch (e) {
              reject(new Error('解析钉钉响应失败: ' + e.message))
            }
          },
          /**
           * 请求失败回调
           * 网络层面错误（如超时、DNS 解析失败）
           */
          onerror: function (err) {
            reject(new Error('网络请求失败: ' + (err.statusText || err.status || '未知错误')))
          },
          /**
           * 请求超时回调，默认 15 秒超时
           */
          ontimeout: function () {
            reject(new Error('请求超时，Webhook 地址可能不可达'))
          }
        })
      })
    }
  }

  // ================================================================
  // 6. UI 模块
  // ================================================================

  /**
   * UI 模块
   * 在 Cpolar 页面顶部注入配置工具栏，包含 Webhook 配置、刷新间隔、隧道勾选列表和运行状态
   * 所有 UI 元素通过原生 DOM API 创建，不依赖任何 UI 框架
   */
  const UI = {
    /** 配置栏容器元素，保存引用以便后续更新状态 */
    barEl: null,
    /** 隧道列表容器，用于动态更新勾选列表 */
    listEl: null,
    /** 状态显示区域，展示上次推送时间和运行状态 */
    statusEl: null,
    /** 启动/停止按钮 */
    toggleBtn: null,
    /** Webhook URL 输入框 */
    urlInput: null,
    /** 刷新间隔输入框 */
    intervalInput: null,

    /**
     * 注入全局样式
     * 使用 GM_addStyle 将样式注入到页面，避免与页面现有样式冲突
     * 所有选择器都加上 [data-cpolar-sync] 属性前缀以防污染
     */
    injectStyles: function () {
      var css = `
        [data-cpolar-sync] {
          all: initial;
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
          font-size: 14px;
          color: #333;
          box-sizing: border-box;
        }
        [data-cpolar-sync] *,
        [data-cpolar-sync] *::before,
        [data-cpolar-sync] *::after {
          box-sizing: border-box;
        }
        .cpolar-sync-bar {
          position: relative;
          z-index: 99999;
          background: #fff;
          border-bottom: 2px solid #1a7f37;
          box-shadow: 0 2px 12px rgba(0,0,0,0.15);
          padding: 12px 20px;
          margin-bottom: 8px;
        }
        .cpolar-sync-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 10px;
          cursor: pointer;
          user-select: none;
        }
        .cpolar-sync-title {
          font-size: 16px;
          font-weight: 600;
          color: #1a7f37;
          display: flex;
          align-items: center;
          gap: 8px;
        }
        .cpolar-sync-toggle-btn {
          background: #1a7f37;
          color: #fff;
          border: none;
          border-radius: 4px;
          padding: 6px 16px;
          font-size: 13px;
          cursor: pointer;
          transition: background 0.2s;
        }
        .cpolar-sync-toggle-btn:hover {
          background: #145c26;
        }
        .cpolar-sync-toggle-btn.stopped {
          background: #d9534f;
        }
        .cpolar-sync-toggle-btn.stopped:hover {
          background: #c9302c;
        }
        .cpolar-sync-body {
          display: none;
        }
        .cpolar-sync-body.open {
          display: block;
        }
        .cpolar-sync-row {
          display: flex;
          align-items: center;
          gap: 12px;
          margin-bottom: 8px;
          flex-wrap: wrap;
        }
        .cpolar-sync-label {
          font-size: 13px;
          color: #555;
          white-space: nowrap;
          min-width: 80px;
        }
        .cpolar-sync-input {
          flex: 1;
          min-width: 200px;
          padding: 6px 10px;
          border: 1px solid #d9d9d9;
          border-radius: 4px;
          font-size: 13px;
          outline: none;
          transition: border-color 0.2s;
        }
        .cpolar-sync-input:focus {
          border-color: #1a7f37;
          box-shadow: 0 0 0 2px rgba(26,127,55,0.15);
        }
        .cpolar-sync-input-short {
          width: 80px;
          padding: 6px 10px;
          border: 1px solid #d9d9d9;
          border-radius: 4px;
          font-size: 13px;
          outline: none;
        }
        .cpolar-sync-input-short:focus {
          border-color: #1a7f37;
        }
        .cpolar-sync-table-wrap {
          max-height: 300px;
          overflow-y: auto;
          border: 1px solid #e8e8e8;
          border-radius: 4px;
          margin-top: 8px;
        }
        .cpolar-sync-table {
          width: 100%;
          border-collapse: collapse;
          font-size: 13px;
        }
        .cpolar-sync-table th {
          background: #fafafa;
          padding: 8px 10px;
          text-align: left;
          font-weight: 600;
          color: #555;
          border-bottom: 1px solid #e8e8e8;
          position: sticky;
          top: 0;
          z-index: 1;
        }
        .cpolar-sync-table td {
          padding: 6px 10px;
          border-bottom: 1px solid #f0f0f0;
        }
        .cpolar-sync-table tr:hover td {
          background: #f5fcf5;
        }
        .cpolar-sync-table input[type="checkbox"] {
          cursor: pointer;
          width: 16px;
          height: 16px;
        }
        .cpolar-sync-status {
          margin-top: 6px;
          width: 100%;
        }
        .cpolar-sync-status table {
          width: 100%;
          border-collapse: collapse;
          font-size: 12px;
          table-layout: fixed;
        }
        .cpolar-sync-status th {
          background: #fafafa;
          padding: 6px 10px;
          text-align: left;
          font-weight: 600;
          color: #555;
          border-bottom: 1px solid #e8e8e8;
          white-space: nowrap;
          font-size: 12px;
        }
        .cpolar-sync-status td {
          padding: 5px 10px;
          color: #555;
          border-bottom: 1px solid #f0f0f0;
          white-space: nowrap;
          font-size: 12px;
        }
        .cpolar-sync-status td.running {
          color: #1a7f37;
        }
        .cpolar-sync-status td.stopped {
          color: #d9534f;
        }
        .cpolar-sync-status tr:hover td {
          background: #f5fcf5;
        }
        .cpolar-sync-status-dot {
          width: 8px;
          height: 8px;
          border-radius: 50%;
          display: inline-block;
        }
        .cpolar-sync-status-dot.running {
          background: #1a7f37;
        }
        .cpolar-sync-status-dot.stopped {
          background: #d9534f;
        }
        .cpolar-sync-save-btn {
          background: #1677ff;
          color: #fff;
          border: none;
          border-radius: 4px;
          padding: 6px 16px;
          font-size: 13px;
          cursor: pointer;
          transition: background 0.2s;
        }
        .cpolar-sync-save-btn:hover {
          background: #0958d9;
        }
        .cpolar-sync-msg {
          font-size: 12px;
          color: #999;
          margin-left: 8px;
        }
        .cpolar-sync-msg.success {
          color: #1a7f37;
        }
        .cpolar-sync-msg.error {
          color: #d9534f;
        }
        .cpolar-sync-overlay {
          position: fixed;
          top: 0; left: 0; right: 0; bottom: 0;
          background: rgba(0,0,0,0.45);
          z-index: 999999;
          display: flex;
          align-items: flex-start;
          justify-content: center;
          padding-top: 60px;
        }
        .cpolar-sync-modal {
          background: #fff;
          border-radius: 8px;
          box-shadow: 0 8px 30px rgba(0,0,0,0.25);
          width: 640px;
          max-width: 90vw;
          max-height: 80vh;
          display: flex;
          flex-direction: column;
        }
        .cpolar-sync-modal-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 14px 20px;
          border-bottom: 1px solid #e8e8e8;
          font-size: 15px;
          font-weight: 600;
          color: #333;
        }
        .cpolar-sync-modal-close {
          cursor: pointer;
          font-size: 18px;
          color: #999;
          line-height: 1;
          border: none;
          background: none;
          padding: 0 4px;
        }
        .cpolar-sync-modal-close:hover {
          color: #333;
        }
        .cpolar-sync-modal-body {
          padding: 16px 20px;
          overflow-y: auto;
          flex: 1;
          font-size: 13px;
          line-height: 1.6;
          white-space: pre-wrap;
          word-break: break-all;
          color: #333;
        }
      `
      GM_addStyle(css)
    },

    /**
     * 将配置栏插入到页面主内容区域，避开左侧导航栏
     * 由于 Vue SPA 在 document-end 时尚未渲染，此处仅做兜底插入
     * （append 到 document.body 末尾），
     * 等页面渲染完成后由 repositionBar 重新定位到正确的主内容区
     * @param {Element} el - 要插入的配置栏 DOM 元素
     */
    _insertIntoContentArea: function (el) {
      /**
       * 尝试探测侧边栏宽度，但此时 Vue 可能未渲染完成，
       * 因此探测结果可能不准确，仅做初步偏移
       */
      var sidebarWidth = this._detectSidebarWidth()
      Log.info('[Sidebar]', '初始探测侧边栏宽度: ' + sidebarWidth + 'px')

      /** 设置初步偏移量 */
      if (sidebarWidth > 0) {
        el.style.marginLeft = sidebarWidth + 'px'
        el.style.width = 'calc(100% - ' + sidebarWidth + 'px)'
        Log.log('[Sidebar]', '初始 marginLeft=' + sidebarWidth + 'px')
      }

      /**
       * Vue SPA 在 document-end 时 #app 通常尚未渲染子元素，
       * 所以不能在此插入 #app 内部。改为 append 到 body 末尾，
       * 等 Vue 渲染完成后再由 repositionBar 重新定位。
       * 初始设为隐藏防止闪现
       */
      el.style.display = 'none'
      document.body.appendChild(el)
      Log.log('[DOM]', '初始插入到 document.body 末尾（隐藏状态，等待 Vue 渲染后重新定位）')
    },

    /**
     * 递进查找主内容容器
     * 从父元素开始，在子元素中从后向前查找非侧边栏的元素。
     * 如果全部子元素都被判定为侧边栏，则取第一个子元素递进到其内部继续查找，
     * 最多递进 3 层以防止死循环
     * @param {Element} parent - 起始父元素
     * @param {number} depth - 当前递归深度（内部使用）
     * @returns {Element|null} 找到的内容容器，或 null
     */
    _findContentContainer: function (parent, depth) {
      depth = depth || 0
      if (depth > 3) {
        Log.warn('[DOM]', '递进查找已达最大深度 3，停止')
        return null
      }

      var skipKeywords = ['sidebar', 'menu', 'aside', 'sider']
      var children = parent.children

      /** 从后向前找非侧边栏子元素 */
      for (var i = children.length - 1; i >= 0; i--) {
        var child = children[i]
        var cls = String(child.className || '') + ' ' + (child.id || '')
        var isSidebar = skipKeywords.some(function (kw) {
          return cls.toLowerCase().indexOf(kw) !== -1
        })
        if (!isSidebar) {
          Log.dumpElement('[DOM]', '查找命中 [' + depth + ']: <' + child.tagName + '>', child)
          return child
        }
      }

      /** 全部被判定为侧边栏 → 取第一个子元素（通常是最外层 wrapper）递进 */
      if (children.length > 0) {
        var first = children[0]
        Log.log('[DOM]', '[' + depth + '] 全部子元素像侧边栏，递进到 <' + first.tagName + '> 内部查找 (depth=' + (depth + 1) + ')')
        return this._findContentContainer(first, depth + 1)
      }

      return null
    },

    /**
     * 重新定位配置栏到正确的主内容区域
     * 在 Vue SPA 渲染完成后调用，此时侧边栏和内容区已在 DOM 中，
     * 可以准确探测侧边栏宽度并找到主内容容器
     */
    repositionBar: function () {
      var el = this.barEl
      if (!el) {
        Log.warn('[DOM]', 'repositionBar: barEl 不存在')
        return
      }

      /** 重新探测侧边栏宽度（此时 Vue 已渲染，结果应准确） */
      var sidebarWidth = this._detectSidebarWidth()
      Log.info('[Sidebar]', '重新探测侧边栏宽度: ' + sidebarWidth + 'px')

      /**
       * 查找主内容容器并移动配置栏
       * 策略：在 #app 中从后向前找非侧边栏的子元素作为目标容器
       * 如果全部子元素都被判定为侧边栏，递进到内部查找
       */
      var targetParent = null
      var app = document.querySelector('#app')

      if (app && app.children.length > 0) {
        targetParent = this._findContentContainer(app)
        if (!targetParent) {
          Log.warn('[DOM]', '递进查找失败，回退到 #app 开头')
          targetParent = app
        }
      } else if (app) {
        /** #app 存在但无子元素（极端情况） */
        targetParent = app
        Log.warn('[DOM]', '#app 仍无子元素，插入 #app 开头')
      } else {
        /** 无 #app，尝试用 body 的最后一个宽子元素 */
        var bodyChildren = document.body.children
        if (bodyChildren.length > 1) {
          targetParent = bodyChildren[bodyChildren.length - 1]
          Log.log('[DOM]', '无 #app，插入到 body 末子元素')
        } else {
          targetParent = document.body
          Log.log('[DOM]', '回退到 document.body')
        }
      }

      /** 移动配置栏到目标容器开头 */
      if (el.parentNode) {
        el.parentNode.removeChild(el)
      }
      targetParent.insertBefore(el, targetParent.firstChild)

      /**
       * 用 margin-left 在侧边栏和内容区之间留出视觉间距，
       * 而非 padding（padding 会让配置栏白条变宽）。
       */
      el.style.marginLeft = '20px'
      el.style.width = ''
      el.style.paddingLeft = ''
      el.style.paddingRight = ''

      /** 重新定位完成，显示配置栏（block 覆盖 all:initial 的 inline 重置） */
      el.style.display = 'block'
      Log.log('[DOM]', '配置栏已移动到 <' + targetParent.tagName + '> 开头并显示')
    },

    /**
     * 探测左侧导航栏的实际宽度
     * 遍历页面中所有元素，查找 position:fixed/absolute 且位于左侧 0 位置的元素，
     * 取最宽的那个作为侧边栏宽度。此方法不依赖任何类名/标签名猜测，
     * 能适配任意页面结构
     * @returns {number} 侧边栏宽度（像素），未找到返回 220
     */
    _detectSidebarWidth: function () {
      /** 收集所有可能为侧边栏的元素宽度 */
      var widths = []

      /**
       * 遍历所有元素，筛选 fixed/absolute 定位且紧贴左侧的元素
       * 使用 TreeWalker 比 querySelectorAll('*') 更高效
       */
      var walker = document.createTreeWalker(
        document.body,
        NodeFilter.SHOW_ELEMENT,
        null,
        false
      )
      while (walker.nextNode()) {
        var node = walker.currentNode
        /** 跳过脚本、样式等不可见元素 */
        var tag = node.tagName.toLowerCase()
        if (tag === 'script' || tag === 'style' || tag === 'link' || tag === 'meta') {
          continue
        }

        var style = window.getComputedStyle(node)
        /** 只检查 fixed 或 absolute 定位的元素 */
        if (style.position !== 'fixed' && style.position !== 'absolute') {
          continue
        }

        var rect = node.getBoundingClientRect()
        /**
         * 侧边栏特征：
         * - left == 0（紧贴左侧）
         * - 宽度 100~500px（合理的侧边栏宽度范围）
         * - 高度 > 200px（排除顶部导航条等矮元素）
         * - visibility 不为 hidden
         */
        if (rect.left === 0 && rect.width >= 100 && rect.width <= 500 &&
            rect.height > 200 && style.visibility !== 'hidden' &&
            style.display !== 'none') {
          widths.push(rect.width)
          Log.log('[Sidebar]', '候选 fixed/absolute 元素: <' + tag + '> id=' + (node.id || '(无)') + ' class=' + (node.className || '').substring(0, 40) + ' w=' + rect.width + ' h=' + rect.height)
        }
      }

      /** 取最宽的作为侧边栏宽度（最宽的那个通常是主侧边栏） */
      if (widths.length > 0) {
        var maxW = Math.max.apply(null, widths)
        Log.log('[Sidebar]', 'fixed/absolute 候选宽度列表: [' + widths.join(', ') + '], 取最宽: ' + maxW + 'px')
        return maxW
      }

      /**
       * 没有找到 fixed/absolute 的侧边栏，尝试找正常流中的侧边栏
       * 查找 #app 下 left=0 且高度 > 200px 的子元素
       */
      var app = document.querySelector('#app')
      if (app) {
        var children = app.children
        for (var i = 0; i < children.length; i++) {
          var r = children[i].getBoundingClientRect()
          if (r.left === 0 && r.width >= 100 && r.width <= 500 && r.height > 200) {
            Log.log('[Sidebar]', '#app 子元素命中侧边栏: [' + i + '] <' + children[i].tagName + '> id=' + (children[i].id || '(无)') + ' w=' + r.width + ' h=' + r.height)
            return r.width
          }
        }
      }

      /** 回退：Element UI 默认侧边栏宽度 */
      Log.warn('[Sidebar]', '未探测到侧边栏，使用默认值 220px')
      return 220
    },

    /**
     * 创建并注入配置栏到页面最顶部
     * 自动检测主内容容器插入，避开左侧导航栏
     * @param {Object} config - 当前配置对象，用于回填到表单
     */
    createBar: function (config) {
      /** 安全防护：登录页面不创建配置栏 */
      if (Monitor._isLoginPage()) {
        Log.log('[UI]', 'createBar 跳过：当前为登录页面')
        return
      }
      /** 创建配置栏容器，通过 _insertIntoContentArea 插入到主内容区 */
      var bar = document.createElement('div')
      bar.setAttribute('data-cpolar-sync', '')
      bar.className = 'cpolar-sync-bar'
      bar.id = 'cpolar-sync-bar'

      /** 标题行（可点击折叠） */
      var header = document.createElement('div')
      header.className = 'cpolar-sync-header'

      var title = document.createElement('div')
      title.className = 'cpolar-sync-title'
      title.textContent = '📡 Cpolar 隧道状态同步'

      header.appendChild(title)

      /** 可折叠内容区域 */
      var body = document.createElement('div')
      body.className = 'cpolar-sync-body open'
      body.id = 'cpolar-sync-body'

      /** 行1：Webhook URL */
      var row1 = this._createInputRow('Webhook URL', 'url', config.webhookUrl, 'https://oapi.dingtalk.com/robot/send?access_token=...')

      /** 行2：刷新间隔 */
      var row2 = this._createInputRow('刷新间隔', 'interval', String(config.interval), '分钟')

      /** 行3：操作按钮 */
      var row3 = document.createElement('div')
      row3.className = 'cpolar-sync-row'

      var saveBtn = document.createElement('button')
      saveBtn.className = 'cpolar-sync-save-btn'
      saveBtn.textContent = '💾 保存配置'
      row3.appendChild(saveBtn)

      var scanBtn = document.createElement('button')
      scanBtn.className = 'cpolar-sync-save-btn'
      scanBtn.style.marginLeft = '8px'
      scanBtn.textContent = '🔄 扫描隧道'
      row3.appendChild(scanBtn)

      var previewBtn = document.createElement('button')
      previewBtn.className = 'cpolar-sync-save-btn'
      previewBtn.style.marginLeft = '8px'
      previewBtn.textContent = '👁 预览信息'
      row3.appendChild(previewBtn)

      var sendBtn = document.createElement('button')
      sendBtn.className = 'cpolar-sync-save-btn'
      sendBtn.style.marginLeft = '8px'
      sendBtn.style.background = '#d9534f'
      sendBtn.textContent = '📤 立即发送'
      row3.appendChild(sendBtn)

      var toggleBtn = document.createElement('button')
      toggleBtn.className = 'cpolar-sync-save-btn'
      toggleBtn.style.marginLeft = '8px'
      toggleBtn.style.background = config.enabled ? '#1a7f37' : '#d9534f'
      toggleBtn.textContent = config.enabled ? '⏹ 停止监控' : '▶ 启动监控'
      this.toggleBtn = toggleBtn
      row3.appendChild(toggleBtn)

      /** 调试日志切换按钮 */
      var debugBtn = document.createElement('button')
      debugBtn.className = 'cpolar-sync-save-btn'
      debugBtn.id = 'cpolar-sync-debug-btn'
      debugBtn.style.marginLeft = '8px'
      debugBtn.style.background = '#6c757d'
      debugBtn.textContent = '🔍 调试日志'
      row3.appendChild(debugBtn)

      debugBtn.addEventListener('click', function () {
        var cfg = Store.loadConfig()
        cfg.debug = !cfg.debug
        Store.saveConfig(cfg)
        debugBtn.style.background = cfg.debug ? '#1a7f37' : '#6c757d'
        /** 即时更新状态栏中的调试日志状态 */
        var debugEl = document.getElementById('cpolar-sync-debug-status')
        if (debugEl) {
          var isOn = cfg.debug === true
          debugEl.className = isOn ? 'running' : ''
          var dd = debugEl.querySelector('.cpolar-sync-status-dot')
          if (dd) dd.className = 'cpolar-sync-status-dot ' + (isOn ? 'running' : 'stopped')
          var tn = debugEl.childNodes[1]
          if (tn) tn.textContent = isOn ? '已开启' : '已关闭'
        }
        Log.info('[UI]', '调试日志开关已切换: ' + (cfg.debug ? '开启' : '关闭'))
        if (cfg.debug) {
          setTimeout(function () {
            Log.dumpPageLayout()
          }, 500)
        }
      })

      /** 操作反馈消息区域 */
      var msgSpan = document.createElement('span')
      msgSpan.className = 'cpolar-sync-msg'
      msgSpan.id = 'cpolar-sync-msg'
      row3.appendChild(msgSpan)

      body.appendChild(row1)
      body.appendChild(row2)
      body.appendChild(row3)

      /** 行4：隧道列表 */
      var row4 = document.createElement('div')
      row4.className = 'cpolar-sync-row'
      row4.style.flexDirection = 'column'
      row4.style.alignItems = 'stretch'

      var listLabel = document.createElement('span')
      listLabel.className = 'cpolar-sync-label'
      listLabel.textContent = '监控隧道（勾选需要推送的隧道）'
      row4.appendChild(listLabel)

      var tableWrap = document.createElement('div')
      tableWrap.className = 'cpolar-sync-table-wrap'
      tableWrap.id = 'cpolar-sync-table-wrap'
      row4.appendChild(tableWrap)

      body.appendChild(row4)

      /** 行5：状态栏 */
      var row5 = document.createElement('div')
      row5.className = 'cpolar-sync-row'
      var statusEl = this._createStatusEl(config.enabled)
      this.statusEl = statusEl
      row5.appendChild(statusEl)
      body.appendChild(row5)

      bar.appendChild(header)
      bar.appendChild(body)

      /** 将配置栏插入到主内容区最前面，避开左侧导航栏 */
      this._insertIntoContentArea(bar)

      this.barEl = bar
      this.bodyEl = body
      this.urlInput = row1.querySelector('.cpolar-sync-input')
      this.intervalInput = row2.querySelector('.cpolar-sync-input-short')

      /** 延迟安全检测：创建后 2 秒若发现仍在登录页，自动移除 */
      setTimeout(function () {
        if (Monitor._isLoginPage()) {
          Log.warn('[UI]', '检测到登录页，移除已创建的配置栏')
          if (this.barEl && this.barEl.parentNode) {
            this.barEl.parentNode.removeChild(this.barEl)
          }
        }
      }.bind(this), 2000)

      /** 绑定事件：可折叠的标题栏点击 */
      header.addEventListener('click', function (e) {
        /** 点击按钮时不触发折叠 */
        if (e.target.tagName === 'BUTTON') return
        body.classList.toggle('open')
      })

      /** 绑定事件：保存配置 */
      saveBtn.addEventListener('click', function () {
        this._handleSave()
      }.bind(this))

      /** 绑定事件：扫描隧道 */
      scanBtn.addEventListener('click', function () {
        this._handleScan()
      }.bind(this))

      /** 绑定事件：启动/停止 */
      toggleBtn.addEventListener('click', function () {
        this._handleToggle()
      }.bind(this))

      /** 绑定事件：预览 */
      previewBtn.addEventListener('click', function () {
        this._handlePreview()
      }.bind(this))

      /** 绑定事件：立即发送 */
      sendBtn.addEventListener('click', function () {
        this._handleSendNow()
      }.bind(this))

      this.listEl = tableWrap
    },

    /**
     * 创建带标签和输入框的一行
     * @param {string} labelText - 标签文字
     * @param {string} type - 输入类型标识（url/interval）
     * @param {string} value - 输入框初始值
     * @param {string} suffix - 输入框后缀提示文字
     * @returns {Element} 行容器元素
     */
    _createInputRow: function (labelText, type, value, suffix) {
      var row = document.createElement('div')
      row.className = 'cpolar-sync-row'

      var label = document.createElement('span')
      label.className = 'cpolar-sync-label'
      label.textContent = labelText
      row.appendChild(label)

      if (type === 'url') {
        var input = document.createElement('input')
        input.type = 'text'
        input.className = 'cpolar-sync-input'
        input.placeholder = suffix
        input.value = value || ''
        row.appendChild(input)
      } else if (type === 'interval') {
        var inputShort = document.createElement('input')
        inputShort.type = 'number'
        inputShort.className = 'cpolar-sync-input-short'
        inputShort.min = 5
        inputShort.max = 360
        inputShort.value = value || '30'
        row.appendChild(inputShort)

        var hint = document.createElement('span')
        hint.style.fontSize = '12px'
        hint.style.color = '#999'
        hint.textContent = '（最小 5 分钟）'
        row.appendChild(hint)
      }

      return row
    },

    /**
     * 创建状态显示元素
     * @param {boolean} isRunning - 是否正在运行
     * @returns {Element} 状态元素
     */

    /**
     * 从隧道列表（el-table）读取列宽比例，使状态表格与之视觉一致
     */
    _getTunnelTableColWidths: function () {
      var defWidths = ['12%', '18%', '18%', '18%', '17%', '17%']
      try {
        /** 测量监控隧道列表（.cpolar-sync-table）表头的各列实际宽度 */
        var headerRow = document.querySelector('.cpolar-sync-table thead tr')
        if (!headerRow) return defWidths
        var headerCells = headerRow.querySelectorAll('th')
        if (!headerCells || headerCells.length < 6) return defWidths
        var total = 0
        var widths = []
        for (var i = 0; i < 6; i++) {
          var w = headerCells[i].getBoundingClientRect().width
          if (isNaN(w) || w <= 0) return defWidths
          widths.push(w)
          total += w
        }
        if (total <= 0) return defWidths
        return widths.map(function (w) {
          return (w / total * 100).toFixed(1) + '%'
        })
      } catch (e) {
        return defWidths
      }
    },

    /**
     * 同步状态表格列宽与隧道列表一致
     * 在隧道列表渲染完成后调用，读取实际 <col> 宽度并更新状态表格 <colgroup>
     */
    _syncStatusColWidths: function () {
      var widths = this._getTunnelTableColWidths()
      var statusTable = document.querySelector('#cpolar-sync-status table')
      if (!statusTable) return
      var colGroup = statusTable.querySelector('colgroup')
      if (!colGroup) return
      var cols = colGroup.querySelectorAll('col')
      if (!cols || cols.length < widths.length) return
      for (var i = 0; i < widths.length; i++) {
        cols[i].style.width = widths[i]
      }
      Log.log('[UI]', '同步状态表格列宽: ' + widths.join(', ') + ' (隧道列表原始像素: ' + this._getTunnelRawPixelWidths().join(', ') + ')')
    },

    /**
     * 读取隧道列表原始像素列宽，供调试
     * @returns {Array}
     */
    _getTunnelRawPixelWidths: function () {
      try {
        var headerRow = document.querySelector('.cpolar-sync-table thead tr')
        if (!headerRow) return []
        var cells = headerRow.querySelectorAll('th')
        if (!cells || cells.length < 6) return []
        var result = []
        for (var i = 0; i < 6; i++) {
          result.push(String(Math.round(cells[i].getBoundingClientRect().width)))
        }
        return result
      } catch (e) {
        return []
      }
    },

    _createStatusEl: function (isRunning) {
      var el = document.createElement('div')
      el.className = 'cpolar-sync-status'
      el.id = 'cpolar-sync-status'

      var table = document.createElement('table')

      /**
       * 从隧道列表（el-table）读取列宽比例，使状态表格与之视觉一致
       */
      var colWidths = this._getTunnelTableColWidths()
      var colGroup = document.createElement('colgroup')
      colWidths.forEach(function (w) {
        var col = document.createElement('col')
        col.style.width = w
        colGroup.appendChild(col)
      })
      table.appendChild(colGroup)

      var thead = document.createElement('thead')
      var headRow = document.createElement('tr')
      var headers = ['当前状态', '上次检测', '上次推送', '检测结果', '下次检测', '调试日志']
      headers.forEach(function (h) {
        var th = document.createElement('th')
        th.textContent = h
        headRow.appendChild(th)
      })
      thead.appendChild(headRow)
      table.appendChild(thead)

      /** 数据行 */
      var tbody = document.createElement('tbody')
      var dataRow = document.createElement('tr')

      var statusCell = document.createElement('td')
      statusCell.className = isRunning ? 'running' : 'stopped'
      statusCell.id = 'cpolar-sync-status-value'
      var dot = document.createElement('span')
      dot.className = 'cpolar-sync-status-dot ' + (isRunning ? 'running' : 'stopped')
      dot.id = 'cpolar-sync-status-dot'
      dot.style.marginRight = '6px'
      statusCell.insertBefore(dot, statusCell.firstChild)
      statusCell.appendChild(document.createTextNode(isRunning ? '运行中' : '已停止'))

      /** 调试日志状态单元格（带绿点，样式同运行状态） */
      var debugCell = document.createElement('td')
      debugCell.id = 'cpolar-sync-debug-status'
      var debugDot = document.createElement('span')
      debugDot.className = 'cpolar-sync-status-dot ' + (false ? 'running' : 'stopped')
      debugDot.style.marginRight = '6px'
      debugCell.appendChild(debugDot)
      debugCell.appendChild(document.createTextNode('已关闭'))

      var cells = [
        statusCell,
        { id: 'cpolar-sync-check-time', text: '--' },
        { id: 'cpolar-sync-push-time', text: '--' },
        { id: 'cpolar-sync-check-result', text: '--' },
        { id: 'cpolar-sync-next-time', text: '--' },
        debugCell
      ]
      cells.forEach(function (c) {
        /** statusCell 已是 <td>，直接追加到行，不再次包装 */
        if (c.tagName === 'TD') {
          dataRow.appendChild(c)
        } else {
          var td = document.createElement('td')
          if (c.id) td.id = c.id
          td.textContent = c.text || '--'
          dataRow.appendChild(td)
        }
      })

      tbody.appendChild(dataRow)
      table.appendChild(tbody)
      el.appendChild(table)
      return el
    },

    /**
     * 渲染隧道列表（表格形式）
     * @param {Array} tunnels - 隧道数据数组
     * @param {Array} selectedNames - 已勾选的隧道名称列表
     */
    renderTunnelList: function (tunnels, selectedNames) {
      /** 清空容器 */
      this.listEl.innerHTML = ''

      /** 无可展示隧道时显示提示 */
      if (!tunnels || tunnels.length === 0) {
        this.listEl.innerHTML = '<div style="padding:20px;text-align:center;color:#999;">暂无隧道数据，请确认是否在在线状态页面</div>'
        return
      }

      /** 创建表格 */
      var table = document.createElement('table')
      table.className = 'cpolar-sync-table'

      /** 表头 */
      var thead = document.createElement('thead')
      var headRow = document.createElement('tr')
      var headers = ['', '隧道名称', '协议', '公网地址', '本地地址', '创建时间']
      headers.forEach(function (h) {
        var th = document.createElement('th')
        th.textContent = h
        headRow.appendChild(th)
      })
      thead.appendChild(headRow)
      table.appendChild(thead)

      /** 表体 */
      var tbody = document.createElement('tbody')
      var self = this
      tunnels.forEach(function (t) {
        var tr = document.createElement('tr')

        /** 勾选框列 */
        var tdCheck = document.createElement('td')
        var checkbox = document.createElement('input')
        checkbox.type = 'checkbox'
        /** 用 name|protocol 作为唯一标识 */
        var tunnelId = Parser.getTunnelId(t)
        checkbox.checked = selectedNames.indexOf(tunnelId) !== -1
        checkbox.dataset.tunnelName = t.name
        checkbox.dataset.tunnelId = tunnelId
        checkbox.dataset.tunnelProtocol = t.protocol || ''

        /** 勾选变更时自动保存 */
        checkbox.addEventListener('change', function () {
          self._handleCheckboxChange()
        })

        tdCheck.appendChild(checkbox)
        tr.appendChild(tdCheck)

        /** 数据列 */
        var fields = ['name', 'protocol', 'publicUrl', 'localAddr', 'createTime']
        fields.forEach(function (f) {
          var td = document.createElement('td')
          td.textContent = t[f] || '-'
          tr.appendChild(td)
        })

        tbody.appendChild(tr)
      })
      table.appendChild(tbody)
      this.listEl.appendChild(table)
    },

    /**
     * 更新状态显示
     * @param {Object} status - 状态对象 { isRunning, lastCheckTime, lastCheckStatus, lastPushTime, nextCheckTime, message }
     */
    updateStatus: function (status) {
      var dot = document.getElementById('cpolar-sync-status-dot')
      var statusValue = document.getElementById('cpolar-sync-status-value')

      if (dot && statusValue) {
        dot.className = 'cpolar-sync-status-dot ' + (status.isRunning ? 'running' : 'stopped')
        statusValue.className = status.isRunning ? 'running' : 'stopped'
        /** 保留 dot 元素，只更新后面的文本 */
        var txtNode = statusValue.childNodes[1]
        if (txtNode) {
          txtNode.textContent = status.isRunning ? '运行中' : '已停止'
        } else {
          statusValue.appendChild(document.createTextNode(status.isRunning ? '运行中' : '已停止'))
        }
      }

      /** 更新各信息字段 */
      if (status.lastCheckTime) {
        var checkEl = document.getElementById('cpolar-sync-check-time')
        if (checkEl) checkEl.textContent = status.lastCheckTime
      }
      if (status.lastCheckStatus) {
        var resultEl = document.getElementById('cpolar-sync-check-result')
        if (resultEl) resultEl.textContent = status.lastCheckStatus
      }
      if (status.lastPushTime) {
        var pushEl = document.getElementById('cpolar-sync-push-time')
        if (pushEl) pushEl.textContent = status.lastPushTime
      }
      if (status.nextCheckTime) {
        var nextEl = document.getElementById('cpolar-sync-next-time')
        if (nextEl) nextEl.textContent = status.nextCheckTime
      }
      /** 更新调试日志状态（含绿点） */
      var debugEl = document.getElementById('cpolar-sync-debug-status')
      if (debugEl) {
        var cfg = Store.loadConfig()
        var isDebugOn = cfg.debug === true
        debugEl.className = isDebugOn ? 'running' : ''
        var debugDot = debugEl.querySelector('.cpolar-sync-status-dot')
        if (debugDot) {
          debugDot.className = 'cpolar-sync-status-dot ' + (isDebugOn ? 'running' : 'stopped')
        }
        var txtNode = debugEl.childNodes[1]
        if (txtNode) {
          txtNode.textContent = isDebugOn ? '已开启' : '已关闭'
        }
      }

      /** 更新启动/停止按钮状态 */
      if (this.toggleBtn) {
        this.toggleBtn.className = 'cpolar-sync-save-btn'
        this.toggleBtn.style.background = status.isRunning ? '#1a7f37' : '#d9534f'
        this.toggleBtn.textContent = status.isRunning ? '⏹ 停止监控' : '▶ 启动监控'
      }

      /** 每次更新状态时同步持久化，刷新后可恢复显示 */
      Monitor._saveStatus()
    },

    /**
     * 显示短暂的操作反馈消息
     * @param {string} msg - 消息内容
     * @param {string} type - 消息类型（success/error），影响颜色
     */
    showMessage: function (msg, type) {
      var el = document.getElementById('cpolar-sync-msg')
      if (!el) return
      el.textContent = msg
      el.className = 'cpolar-sync-msg' + (type ? ' ' + type : '')
      /** 3 秒后自动清除消息 */
      clearTimeout(this._msgTimer)
      this._msgTimer = setTimeout(function () {
        el.textContent = ''
        el.className = 'cpolar-sync-msg'
      }, 3000)
    },

    /**
     * 处理保存按钮点击
     * 将当前表单内容持久化并更新监控配置
     */
    _handleSave: function () {
      var config = Store.loadConfig()
      config.webhookUrl = (this.urlInput && this.urlInput.value.trim()) || ''
      config.interval = Math.max(5, parseInt(this.intervalInput && this.intervalInput.value, 10) || 5)
      /** 回写修正后的值到输入框，防止用户以为设置成功却显示不同数值 */
      if (this.intervalInput) this.intervalInput.value = config.interval
      Store.saveConfig(config)
      this.showMessage('配置已保存 ✓', 'success')

      /** 如果监控正在运行，重新加载配置生效 */
      if (Monitor.timerId) {
        Monitor.stop()
        Monitor.start()
      }
    },

    /**
     * 处理扫描按钮点击
     * 立即解析当前页面 DOM 并更新隧道列表
     */
    _handleScan: function () {
      var tunnels = Parser.parseTunnelList()
      var config = Store.loadConfig()

      if (tunnels.length === 0) {
        this.showMessage('未扫描到隧道数据，请确认页面已加载完成', 'error')
        return
      }

      this.renderTunnelList(tunnels, config.selectedTunnels || [])
      this.showMessage('扫描完成，共发现 ' + tunnels.length + ' 条隧道', 'success')
    },

    /**
     * 处理启动/停止按钮点击
     */
    _handleToggle: function () {
      var config = Store.loadConfig()
      if (config.enabled) {
        /** 当前运行中 → 停止 */
        Monitor.stop()
        this.showMessage('已停止监控', '')
      } else {
        /** 当前已停止 → 启动 */
        if (!config.webhookUrl) {
          this.showMessage('请先配置 Webhook URL', 'error')
          return
        }
        Monitor.start()
        this.showMessage('已启动监控', 'success')
      }
    },

    /**
     * 处理勾选框变更
     * 收集当前所有勾选状态，持久化保存
     */
    _handleCheckboxChange: function () {
      var checkboxes = this.listEl.querySelectorAll('input[type="checkbox"]')
      var selected = []
      checkboxes.forEach(function (cb) {
        if (cb.checked) {
          selected.push(cb.dataset.tunnelId || cb.dataset.tunnelName)
        }
      })

      var config = Store.loadConfig()
      config.selectedTunnels = selected
      Store.saveConfig(config)
    },

    /**
     * 构建预览消息文本（Markdown 格式）
     * 将当前勾选的隧道组装为类似钉钉消息的格式
     */
    _buildPreviewText: function (tunnels) {
      var lines = []
      lines.push('## Cpolar 隧道状态通知（预览）')
      lines.push('')
      lines.push('---')
      lines.push('')
      tunnels.forEach(function (t) {
        lines.push('**' + (t.name || '未命名') + '**')
        if (t.protocol) lines.push('- 协议：' + t.protocol)
        if (t.publicUrl) lines.push('- 公网地址：' + t.publicUrl)
        if (t.localAddr) lines.push('- 本地地址：' + t.localAddr)
        if (t.createTime) lines.push('- 创建时间：' + t.createTime)
        lines.push('')
      })
      var now = new Date()
      var timeStr = now.getFullYear() + '-' +
        String(now.getMonth() + 1).padStart(2, '0') + '-' +
        String(now.getDate()).padStart(2, '0') + ' ' +
        String(now.getHours()).padStart(2, '0') + ':' +
        String(now.getMinutes()).padStart(2, '0') + ':' +
        String(now.getSeconds()).padStart(2, '0')
      lines.push('---')
      lines.push('')
      lines.push('⏱ 检测时间：' + timeStr)
      return lines.join('\n')
    },

    /**
     * 显示预览弹窗
     * @param {string} markdownText - Markdown 格式的预览文本
     */
    _showPreviewModal: function (markdownText) {
      /** 移除已有弹窗 */
      var old = document.getElementById('cpolar-sync-preview')
      if (old) old.parentNode.removeChild(old)

      var overlay = document.createElement('div')
      overlay.className = 'cpolar-sync-overlay'
      overlay.id = 'cpolar-sync-preview'
      overlay.addEventListener('click', function (e) {
        if (e.target === overlay) {
          overlay.parentNode.removeChild(overlay)
        }
      })

      var modal = document.createElement('div')
      modal.className = 'cpolar-sync-modal'

      var header = document.createElement('div')
      header.className = 'cpolar-sync-modal-header'
      header.innerHTML = '<span>📋 推送内容预览</span>'

      var closeBtn = document.createElement('button')
      closeBtn.className = 'cpolar-sync-modal-close'
      closeBtn.textContent = '✕'
      closeBtn.addEventListener('click', function () {
        overlay.parentNode.removeChild(overlay)
      })
      header.appendChild(closeBtn)
      modal.appendChild(header)

      var body = document.createElement('div')
      body.className = 'cpolar-sync-modal-body'
      body.textContent = markdownText
      modal.appendChild(body)

      overlay.appendChild(modal)
      document.body.appendChild(overlay)
    },

    /**
     * 处理预览按钮点击
     * 扫描当前隧道列表，显示推送内容预览
     */
    _handlePreview: function () {
      var tunnels = Parser.parseTunnelList()
      if (tunnels.length === 0) {
        this.showMessage('未扫描到隧道数据，请先扫描', 'error')
        return
      }

      var config = Store.loadConfig()
      var selectedNames = config.selectedTunnels || []
      /** 没有勾选任何隧道时提示，不回退到全选 */
      if (selectedNames.length === 0) {
        this.showMessage('请先在监控隧道列表中勾选需要推送的隧道', 'error')
        return
      }
      var selected = Diff.filterSelected(tunnels, selectedNames)
      if (selected.length === 0) {
        this.showMessage('勾选的隧道未匹配到当前列表，请重新扫描', 'error')
        return
      }

      var text = this._buildPreviewText(selected)
      this._showPreviewModal(text)
      this.showMessage('预览已打开', 'success')
    },

    /**
     * 处理立即发送按钮点击
     * 将当前勾选的隧道立即推送至 Webhook
     */
    _handleSendNow: function () {
      var config = Store.loadConfig()
      if (!config.webhookUrl) {
        this.showMessage('请先配置 Webhook URL', 'error')
        return
      }

      var tunnels = Parser.parseTunnelList()
      if (tunnels.length === 0) {
        this.showMessage('未扫描到隧道数据，请先扫描', 'error')
        return
      }

      var selectedNames = config.selectedTunnels || []
      /** 没有勾选任何隧道时提示，不回退到全选 */
      if (selectedNames.length === 0) {
        this.showMessage('请先在监控隧道列表中勾选需要推送的隧道', 'error')
        return
      }
      var selected = Diff.filterSelected(tunnels, selectedNames)
      if (selected.length === 0) {
        this.showMessage('勾选的隧道未匹配到当前列表，请重新扫描', 'error')
        return
      }

      /** 用户手动强制发送，不校验重复 */
      var diffResult = {
        added: selected,
        updated: [],
        removed: [],
        hasChanges: true
      }

      var message = Notifier.buildDingMsg(diffResult)
      var _this = this

      Notifier.sendWebhook(config.webhookUrl, message).then(function () {
        var now = new Date()
        var timeStr = Monitor._formatTime(now)
        var nextCheck = new Date(now.getTime() + config.interval * 60 * 1000)
        Monitor.lastCheckTime = timeStr
        Monitor.lastCheckStatus = '已推送'
        Monitor.lastPushTime = timeStr
        Monitor.nextCheckTime = Monitor._formatTime(nextCheck)
        Store.saveLastSent(selected)
        UI.updateStatus({
          isRunning: true,
          lastCheckTime: Monitor.lastCheckTime,
          lastCheckStatus: Monitor.lastCheckStatus,
          lastPushTime: Monitor.lastPushTime,
          nextCheckTime: Monitor.nextCheckTime
        })
        _this.showMessage('推送成功（' + selected.length + ' 条隧道）', 'success')
      }).catch(function (err) {
        _this.showMessage('推送失败: ' + err.message, 'error')
      })
    },

    /**
     * 移除配置栏并恢复 body padding
     */
    remove: function () {
      if (this.barEl && this.barEl.parentNode) {
        this.barEl.parentNode.removeChild(this.barEl)
      }
    }
  }

  // ================================================================
  // 7. 主控模块
  // ================================================================

  /**
   * 主控模块
   * 协调各模块工作：定时轮询 → 解析 → 比对 → 推送 → 更新 UI
   * 管理定时器生命周期，处理路由变化
   */
  const Monitor = {
    /** setInterval 定时器 ID */
    timerId: null,
    /** 上次缓存的数据快照，用于变更检测 */
    lastData: null,
    /** 是否为首次启动（首次启动推送全量） */
    isFirstRun: true,
    /** 上次检测时间 */
    lastCheckTime: null,
    /** 上次检测结果描述 */
    lastCheckStatus: '',
    /** 上次推送时间 */
    lastPushTime: null,
    /** 下次检测时间 */
    nextCheckTime: null,
    /** 防止重复调用 _onPageReady */
    _pageReadyPending: false,

    /**
     * 保存当前检测/推送状态到持久化存储（刷新后恢复显示）
     */
    _saveStatus: function () {
      Store.saveStatus({
        lastCheckTime: this.lastCheckTime,
        lastCheckStatus: this.lastCheckStatus,
        lastPushTime: this.lastPushTime,
        nextCheckTime: this.nextCheckTime
      })
    },

    /**
     * 判断当前是否为登录页面
     */
    _isLoginPage: function () {
      var hash = window.location.hash || ''
      var href = window.location.href || ''
      /** URL 检测 */
      if (hash.indexOf('#/login') === 0 || href.indexOf('/login') !== -1) {
        return true
      }
      /** DOM 检测：存在密码输入框 → 登录页 */
      if (document.querySelector('input[type="password"]')) {
        return true
      }
      /** DOM 检测：不存在用户头像 → 未登录 */
      if (document.querySelector('.user-avatar')) {
        return false
      }
      return false
    },

    /**
     * 格式化时间为 HH:mm:ss
     */
    _formatTime: function (date) {
      return String(date.getHours()).padStart(2, '0') + ':' +
        String(date.getMinutes()).padStart(2, '0') + ':' +
        String(date.getSeconds()).padStart(2, '0')
    },

    /**
     * 初始化脚本
     * 注入样式、创建 UI、检测路由、启动或等待
     */
    init: function () {
      /** 注入全局样式（仅 CSS，不产生可见元素） */
      UI.injectStyles()

      /** 从持久化存储恢复配置 */
      var config = Store.loadConfig()
      Log.info('[Init]', '脚本初始化，版本=' + SCRIPT_VERSION + ' debug=' + config.debug)

      /** 
       * 注册路由监听器，由它统一处理 UI 的创建/销毁。
       * init 本身不创建 UI，避免 document-end 时 SPA 尚未稳定导致的闪现
       */
      this._registerRouteListener()
    },

    /**
     * 注册路由变化监听器
     */
    _registerRouteListener: function () {
      /** 记录当前路由，用于轮询检测 SPA 内部导航 */
      var lastHash = window.location.hash

      /**
       * 统一的路由变化处理函数
       * 由初始调用、hashchange 事件和轮询器共同调用
       */
      var handleRouteChange = function () {
        var currentHash = window.location.hash
        if (currentHash === lastHash) return
        lastHash = currentHash

        Log.log('[Init]', '路由变化: ' + currentHash)

        /** 进入登录页面，清理所有状态 */
        if (this._isLoginPage()) {
          Log.log('[Init]', '进入登录页面，清理 UI 并停止监控')
          if (this.timerId) this.stop(false)
          UI.remove()
          return
        }

        var isTargetPage = currentHash === TARGET_ROUTE
        if (isTargetPage) {
          /** 进入在线状态页面，确保 UI 存在 */
          if (!UI.barEl || !UI.barEl.parentNode) {
            var cfg = Store.loadConfig()
            UI.createBar(cfg)
          }
          /** 防止重复初始化 */
          if (this._pageReadyPending) {
            Log.log('[Init]', '_onPageReady 已在等待中，跳过')
          } else {
            this._pageReadyPending = true
            /** 进入目标页面，延迟等待渲染后初始化 */
            Log.log('[Init]', '进入在线状态页面，延迟 1.5s 后初始化')
            setTimeout(function () {
              this._pageReadyPending = false
              var cfg = Store.loadConfig()
              this._onPageReady(cfg)
            }.bind(this), 1500)
          }
        } else {
          /** 离开在线状态页面，仅隐藏 UI，定时器继续运行 */
          Log.log('[Init]', '离开在线状态页面，隐藏 UI')
          this._pageReadyPending = false
          UI.remove()
        }
      }.bind(this)

      /** 
       * 初始触发：处理当前页面路由（SPA 尚未完全挂载时 hash 可能变化，
       * 所以先记录 hash，等 SPA 稳定后再处理）
       */
      setTimeout(function () {
        /** 重置 lastHash 为当前真实 hash，触发 handleRouteChange */
        lastHash = window.location.hash + '__init__'
        handleRouteChange()
      }, 1500)

      /** hashchange 事件（浏览器后退/前进） */
      window.addEventListener('hashchange', function () {
        handleRouteChange()
      }.bind(this))

      /** 
       * SPA 轮询检测（Vue Router 用 pushState 导航时不触发 hashchange）
       */
      setInterval(function () {
        handleRouteChange()
      }.bind(this), 800)
    },

    /**
     * 目标页面就绪时的处理
     * 解析隧道列表 → 渲染 UI → 如果配置已启用则启动定时任务
     * @param {Object} config - 当前配置
     */
    _onPageReady: function (config) {
      var _this = this
      Log.log('[Init]', '目标页面就绪，开始等待表格渲染...')

      /** 调试模式下输出页面布局诊断 */
      Log.dumpPageLayout()

      /** Vue 已渲染，重新定位配置栏到正确的主内容区域 */
      UI.repositionBar()
      Log.log('[Init]', '配置栏重新定位完成')

      /** 恢复上次检测/推送状态 */
      var savedStatus = Store.loadStatus()
      if (savedStatus) {
        if (savedStatus.lastCheckTime) this.lastCheckTime = savedStatus.lastCheckTime
        if (savedStatus.lastCheckStatus) this.lastCheckStatus = savedStatus.lastCheckStatus
        if (savedStatus.lastPushTime) this.lastPushTime = savedStatus.lastPushTime
        if (savedStatus.nextCheckTime) this.nextCheckTime = savedStatus.nextCheckTime
        UI.updateStatus({
          isRunning: config.enabled && config.webhookUrl,
          lastCheckTime: this.lastCheckTime,
          lastCheckStatus: this.lastCheckStatus,
          lastPushTime: this.lastPushTime,
          nextCheckTime: this.nextCheckTime
        })
        Log.log('[Init]', '已恢复上次状态数据')
      }

      /** 等待页面中的表格 DOM 渲染完成 */
      Parser.waitForTable(15000).then(function (found) {
        if (!found) {
          Log.warn('[Init]', '超时未找到隧道列表表格')
          UI.updateStatus({ isRunning: false, message: '未找到隧道列表表格' })
          return
        }
        Log.log('[Init]', '表格已找到，开始解析隧道列表')
        var tunnels = Parser.parseTunnelList()
        UI.renderTunnelList(tunnels, config.selectedTunnels || [])

        /** 隧道列表已渲染，同步状态表格列宽 */
        UI._syncStatusColWidths()

        /** 恢复上次缓存数据用于变更检测 */
        _this.lastData = Store.loadCache()
        _this.isFirstRun = true

        /** 如果配置为已启用状态，自动启动 */
        if (config.enabled && config.webhookUrl) {
          /** 自动恢复：不立即检查，等待首个轮询周期 */
          _this.start(false)
        }
      })
    },

    /**
     * 启动定时监控任务
     * @param {boolean} immediate - 是否立即执行一次检查（默认 true）。
     *   自动恢复时传 false，等待首个轮询周期再检查，避免登录后立即发送
     */
    start: function (immediate) {
      var config = Store.loadConfig()

      /** 清除已有定时器，防止重复启动 */
      if (this.timerId) {
        clearInterval(this.timerId)
      }

      /** 标记为启用 */
      config.enabled = true
      Store.saveConfig(config)

      /** 按配置的间隔启动定时轮询 */
      this.timerId = setInterval(function () {
        this._doTick()
      }.bind(this), config.interval * 60 * 1000)

      /** 首次检查：仅在手动启动时立即执行，自动恢复等首个周期 */
      if (immediate !== false) {
        this._doTick()
      }

      Log.log('[Tick]', '监控启动，间隔=' + config.interval + 'min')

      /** 自动恢复时保留上次存储的检测时间，不从当前时间重新计算 */
      if (immediate === false && this.nextCheckTime) {
        UI.updateStatus({ isRunning: true, lastPushTime: null, nextCheckTime: this.nextCheckTime })
      } else {
        var now = new Date()
        var nextCheck = new Date(now.getTime() + config.interval * 60 * 1000)
        this.nextCheckTime = this._formatTime(nextCheck)
        UI.updateStatus({ isRunning: true, lastPushTime: null, nextCheckTime: this.nextCheckTime })
      }

      UI.showMessage('监控已启动，每 ' + config.interval + ' 分钟检查一次', 'success')
    },

    /**
     * 停止定时监控任务
     * @param {boolean} persistDisabled - 是否将停用状态持久化（默认 true）。
     *   路由切换时传 false，仅停止定时器但不修改配置，切回后可自动恢复
     */
    stop: function (persistDisabled) {
      if (this.timerId) {
        clearInterval(this.timerId)
        this.timerId = null
      }

      /** 路由切换时仅停止定时器，不修改持久化配置（切回后可恢复） */
      if (persistDisabled !== false) {
        var config = Store.loadConfig()
        config.enabled = false
        Store.saveConfig(config)
      }

      Log.log('[Tick]', '监控已停止')
      this.nextCheckTime = null
      UI.updateStatus({ isRunning: false, nextCheckTime: null })
      UI.showMessage('监控已停止', '')
    },

    /**
     * 执行一次检查周期
     * 解析页面 → 筛选勾选隧道 → 检测变更 → 推送 → 更新缓存和 UI
     */
    _doTick: function () {
      var config = Store.loadConfig()
      var now = new Date()
      var timeStr = this._formatTime(now)

      /** 计算下次检测时间 */
      var nextCheck = new Date(now.getTime() + config.interval * 60 * 1000)
      var nextTimeStr = this._formatTime(nextCheck)

      /** 更新追踪字段 */
      this.lastCheckTime = timeStr
      this.nextCheckTime = nextTimeStr

      /** 未配置 Webhook 时跳过 */
      if (!config.webhookUrl) {
        this.lastCheckStatus = '未配置 Webhook URL'
        UI.updateStatus({ isRunning: true, lastCheckTime: timeStr, lastCheckStatus: this.lastCheckStatus, nextCheckTime: nextTimeStr })
        return
      }

      /** 不在在线状态页面时跳过 */
      if (window.location.hash !== TARGET_ROUTE) {
        this.lastCheckStatus = '不在在线状态页面'
        UI.updateStatus({ isRunning: true, lastCheckTime: timeStr, lastCheckStatus: this.lastCheckStatus, nextCheckTime: nextTimeStr })
        return
      }

      /** 解析当前隧道列表 */
      Log.log('[Tick]', '执行一次检查周期')
      var allTunnels = Parser.parseTunnelList()
      if (allTunnels.length === 0) {
        Log.warn('[Tick]', '未解析到隧道数据')
        this.lastCheckStatus = '未解析到隧道数据'
        UI.updateStatus({ isRunning: true, lastCheckTime: timeStr, lastCheckStatus: this.lastCheckStatus, nextCheckTime: nextTimeStr })
        return
      }

      /** 更新 UI 中的隧道列表（保留勾选状态） */
      UI.renderTunnelList(allTunnels, config.selectedTunnels || [])

      /** 未勾选任何隧道时跳过推送 */
      var selectedNames = config.selectedTunnels || []
      if (selectedNames.length === 0) {
        this.lastCheckStatus = '未勾选隧道，不推送'
        UI.updateStatus({ isRunning: true, lastCheckTime: timeStr, lastCheckStatus: this.lastCheckStatus, nextCheckTime: nextTimeStr })
        return
      }

      /** 筛选出用户勾选的隧道 */
      var selectedTunnels = Diff.filterSelected(allTunnels, config.selectedTunnels || [])

      /** 检测数据变更：首次运行时对比上次推送快照，避免重复推送 */
      var oldData = this.isFirstRun ? Store.loadLastSent() : this.lastData
      var diffResult = Diff.detect(oldData, selectedTunnels)

      /** 更新缓存为当前数据（整个列表，不只是勾选的） */
      this.lastData = selectedTunnels
      Store.saveCache(selectedTunnels)
      this.isFirstRun = false

      /** 无变更则跳过推送 */
      if (!diffResult.hasChanges) {
        this.lastCheckStatus = '无变更，已跳过'
        UI.updateStatus({ isRunning: true, lastCheckTime: timeStr, lastCheckStatus: this.lastCheckStatus, nextCheckTime: nextTimeStr })
        return
      }

      /** 构建钉钉消息并发送 */
      var message = Notifier.buildDingMsg(diffResult)
      var webhookUrl = config.webhookUrl
      var _this = this

      Notifier.sendWebhook(webhookUrl, message).then(function () {
        /** 推送成功 */
        var pushNow = new Date()
        var pushTimeStr = _this._formatTime(pushNow)

        /** 重新计算下次检测时间（从推送时刻算起） */
        var pushNext = new Date(pushNow.getTime() + config.interval * 60 * 1000)
        _this.lastPushTime = pushTimeStr
        _this.lastCheckStatus = '已推送'
        _this.nextCheckTime = _this._formatTime(pushNext)

        /** 保存本次推送快照，供下次对比 */
        Store.saveLastSent(selectedTunnels)

        UI.updateStatus({
          isRunning: true,
          lastCheckTime: timeStr,
          lastCheckStatus: _this.lastCheckStatus,
          lastPushTime: pushTimeStr,
          nextCheckTime: _this.nextCheckTime
        })
        UI.showMessage(diffResult.added.length + ' 新增, ' +
          diffResult.updated.length + ' 更新, ' +
          diffResult.removed.length + ' 离线 → 已推送', 'success')
      }).catch(function (err) {
        /** 推送失败 */
        _this.lastCheckStatus = '推送失败'
        UI.updateStatus({
          isRunning: true,
          lastCheckTime: timeStr,
          lastCheckStatus: '推送失败: ' + err.message,
          nextCheckTime: nextTimeStr
        })
        UI.showMessage('推送失败: ' + err.message, 'error')
      })
    }
  }

  // ================================================================
  // 8. 启动入口 & 控制台调试接口
  // ================================================================

  /**
   * 暴露全局调试接口，可在浏览器控制台直接调用：
   *
   *   cpolarSyncDebug(true)  开启调试日志
   *   cpolarSyncDebug(false) 关闭调试日志
   *   cpolarSyncDebug()      查看当前状态
   *   cpolarSyncDebug.layout()  输出页面布局诊断
   */
  window.cpolarSyncDebug = function (enable) {
    var cfg = Store.loadConfig()
    if (enable === true || enable === false) {
      cfg.debug = enable
      Store.saveConfig(cfg)
      console.log('[CpolarSync] 调试日志已' + (enable ? '开启' : '关闭'))
      if (enable) {
        setTimeout(function () {
          Log.dumpPageLayout()
        }, 300)
      }
    } else {
      console.log('[CpolarSync] 当前 debug=' + cfg.debug + ', 使用 cpolarSyncDebug(true/false) 切换')
    }
  }
  window.cpolarSyncDebug.layout = function () {
    Log.dumpPageLayout()
  }

  Monitor.init()
})()
