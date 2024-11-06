const express = require('express');
const fs = require('fs').promises;
const path = require('path');
const PortService = require('./services/port-service');
const router = express.Router();  // 创建路由实例
// 创建Express应用实例
const app = express();
const portService = new PortService();

// 中间件配置
app.use(express.json());
// 静态文件路径修正为项目根目录下的public
app.use(express.static(path.join(__dirname, 'public')));

// 中间件：确保数据文件存在
router.use(async (req, res, next) => {
    try {
        await portService.ensureDataFiles();
        next();
    } catch (error) {
        next(error);
    }
});
// 服务器管理路由
router.get('/get/ports', async (req, res) => {
    try {
        const data = await portService.readJSONFile(portService.PORT_FILE);
        res.json(data);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

router.put('/edit/ports', async (req, res) => {
    try {
        const ports = req.body;
        if (Array.isArray(ports)) {
            await portService.writeJSONFile(portService.PORT_FILE, ports);
            return res.json({ success: true });
        }

        const portWithStatus = {
            ...ports,
        };

        const existingPorts = await portService.readJSONFile(portService.PORT_FILE);
        let updatedPorts;

        const existingPort = existingPorts.find(p => p.port === ports.port);

        if (existingPort) {
            // 更新已存在的端口
            updatedPorts = existingPorts.map(p =>
                p.port === ports.port ? portWithStatus : p
            );
            // 更新端口
            await portService.deletePort(existingPort);
            await portService.addPort(portWithStatus);
        } else {
            // 新增端口
            updatedPorts = [...existingPorts, portWithStatus];
            // 添加端口
            await portService.addPort(portWithStatus);
        }

        if (!portService.isLinux()) {
            await portService.writeJSONFile(portService.PORT_FILE, updatedPorts);
        }
        res.json({
            success: true,
            message: '端口信息保存成功',
            port: portWithStatus
        });

    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});



// 批量添加端口
// router.post('/batch/add/ports', async (req, res) => {
//     try {
//         // 直接使用请求体作为端口数组
//         const ports = req.body;
        
//         if (!Array.isArray(ports)) {
//             return res.status(400).json({
//                 success: false,
//                 message: '无效的端口数据格式'
//             });
//         }

//         // 读取现有端口
//         const existingPorts = await portService.readJSONFile(portService.PORT_FILE);
        
//         // 过滤出新的端口
//         const newPorts = ports.filter(newPort => 
//             !existingPorts.some(existingPort => existingPort.port === newPort.port)
//         );

//         // 合并现有端口和新端口
//         const updatedPorts = [...existingPorts, ...newPorts];

//         // 保存更新后的端口数据
//         await portService.writeJSONFile(portService.PORT_FILE, updatedPorts);

//         res.json({
//             success: true,
//             message: `成功添加 ${newPorts.length} 个端口`,
//             addedPorts: newPorts
//         });

//     } catch (error) {
//         res.status(500).json({
//             success: false,
//             message: `批量添加端口失败: ${error.message}`
//         });
//     }
// });
// 批量更新端口
router.post('/batch/update/ports', async (req, res) => {
    try {
        // 获取请求中的新端口数组
        const newPorts = req.body;

        if (!Array.isArray(newPorts)) {
            return res.status(400).json({
                success: false,
                message: '无效的端口数据格式'
            });
        }

        // 读取现有端口数据
        const existingPorts = await portService.readJSONFile(portService.PORT_FILE);

        // 筛选出新增的端口
        const addedPorts = newPorts.filter(newPort => 
            !existingPorts.some(existingPort => existingPort.port === newPort.port)
        );
        // 添加端口
        await portService.addPortArray(addedPorts);

        // 筛选出配置变更的端口(上传或下载速度不一致)
        const modifiedPorts = newPorts.filter(newPort => {
            const existingPort = existingPorts.find(p => p.port === newPort.port);
            return existingPort && (
                existingPort.upload !== newPort.upload || 
                existingPort.download !== newPort.download
            );
        });
        //删除这些端口
        await portService.deletePortArray(modifiedPorts);
        // 添加这些端口
        await portService.addPortArray(modifiedPorts);


        // 筛选出需要删除的端口(在旧数组中存在但新数组中不存在)
        const deletedPorts = existingPorts.filter(existingPort =>
            !newPorts.some(newPort => newPort.port === existingPort.port)
        );
        // 删除这些端口
        await portService.deletePortArray(deletedPorts);

        if (!portService.isLinux()) {
            //清空再写入新的
            await portService.writeJSONFile(portService.PORT_FILE, []);
            //添加新传入的数组
            await portService.writeJSONFile(portService.PORT_FILE, newPorts);
        }
        res.json({
            success: true,
            changes: {
                added: addedPorts,
                modified: modifiedPorts,
                deleted: deletedPorts
            }
        });

    } catch (error) {
        res.status(500).json({
            success: false,
            message: `端口数据对比失败: ${error.message}`
        });
    }
});

// 删除端口
router.delete('/delete/ports/:port', async (req, res) => {
    try {
        const { port } = req.params;
        
        // 读取现有端口数据
        const existingPorts = await portService.readJSONFile(portService.PORT_FILE);
        
        // 检查端口是否存在
        const portExists = existingPorts.some(p => p.port === port);
        if (!portExists) {
            return res.status(404).json({
                success: false,
                message: '端口不存在'
            });
        }
        // 删除端口
        await portService.deletePort({port});
        // 过滤掉要删除的端口
        const updatedPorts = existingPorts.filter(p => p.port !== port);
        
        // 写入更新后的数据
        if (!portService.isLinux()) {
            await portService.writeJSONFile(portService.PORT_FILE, updatedPorts);
        }

        res.json({
            success: true,
            message: '端口删除成功'
        });

    } catch (error) {
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});
// 删除所有端口
router.delete('/delete-all/ports', async (req, res) => {
    try {
        // 写入空数组以清空所有端口
        await portService.writeJSONFile(portService.PORT_FILE, []);
        // 删除所有端口
        await portService.deleteAllPorts();

        res.json({
            success: true,
            message: '所有端口已清空'
        });

    } catch (error) {
        res.status(500).json({
            success: false,
            message: `清空端口失败: ${error.message}`
        });
    }
});

// 备份数据文件
router.get('/backup', async (req, res) => {
    try {
        const portsData = await fs.readFile(path.join(portService.DATA_DIR, 'port.json'), 'utf8');
        const backupData = JSON.parse(portsData);

        // 生成文件名
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const filename = `port-backup-${timestamp}.json`;

        // 设置响应头
        res.setHeader('Content-Type', 'application/json');
        res.setHeader('Content-Disposition', `attachment; filename=${filename}`);

        // 发送备份数据
        res.json(backupData);

    } catch (error) {
        console.error('备份失败:', error);
        res.status(500).json({
            success: false,
            error: `备份失败: ${error.message}`
        });
    }
});

// 验证密码路由
router.post('/verify-password', async (req, res) => {
    try {
        const { password } = req.body;

        if (!password) {
            return res.status(400).json({
                success: false,
                message: '请提供密码'
            });
        }

        // 获取配置文件中的密码
        const config = await portService.getConfig();

        // 验证密码
        const isValid = password === config.password;

        res.json({
            success: true,
            valid: isValid,
            message: isValid ? '密码验证成功' : '密码错误'
        });

    } catch (error) {
        console.error('验证密码失败:', error);
        res.status(500).json({
            success: false,
            message: `验证密码失败: ${error.message}`
        });
    }
});







// 创建验证中间件
const authMiddleware = async (req, res, next) => {
    try {
        // 如果是验证密码的路由,直接放行
        if (req.path === '/verify-password') {
            return next();
        }

        // 从请求头获取密码
        const password = req.headers['x-api-key'] || req.query.key;

        if (!password) {
            return res.status(401).json({
                success: false,
                message: '未提供访问密码'
            });
        }

        // 获取配置文件中的密码
        const config = await portService.getConfig();

        // 验证密码
        if (password !== config.password) {
            return res.status(403).json({
                success: false,
                message: '访问密码错误'
            });
        }

        // 密码正确，继续处理请求
        next();
    } catch (error) {
        console.error('验证密码时出错:', error);
        res.status(403).json({
            success: false,
            message: '验证过程出错'
        });
    }
};

// 在路由文件中使用
// 先应用验证中间件，再使用路由
app.use('/api', authMiddleware, router);
// 初始化并启动服务器
async function startServer() {
    try {
        console.log('Initializing server...');
        await portService.ensureDataFiles();

        const port = process.env.PORT || 6868;
        app.listen(port, () => {
            console.log(`Server running at http://localhost:${port}`);
            console.log(`Data directory: ${portService.DATA_DIR}`);
        });
    } catch (error) {
        console.error('Failed to start server:', error);
        process.exit(1);
    }
}

startServer();