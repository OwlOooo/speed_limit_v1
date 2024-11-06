const fs = require('fs').promises;
const path = require('path');

class PortService {
    constructor() {
        this.DATA_DIR = path.join(__dirname, '../../data');
        this.PORT_FILE = path.join(this.DATA_DIR, 'port.json');
    }


    // 文件操作方法
    async readJSONFile(filePath) {
        const data = await fs.readFile(filePath, 'utf8');
        return JSON.parse(data);
    }

    async writeJSONFile(filePath, data) {
        await fs.writeFile(filePath, JSON.stringify(data, null, 2));
    }

    async ensureDataFiles() {
        try {
            await fs.mkdir(this.DATA_DIR, { recursive: true });
            for (const file of [this.PORT_FILE]) {
                try {
                    await fs.access(file);
                } catch {
                    await fs.writeFile(file, '[]', 'utf8');
                }
            }
        } catch (error) {
            console.error('Error ensuring data files:', error);
            throw error;
        }
    }
    async getConfig() {
        const configPath = path.join(this.DATA_DIR, 'config.json');
        try {
            const data = await this.readJSONFile(configPath);
            return data;
        } catch (error) {
            console.error('读取配置文件失败:', error);
            // 如果文件不存在，创建默认配置
            const defaultConfig = {
                password: '123456', // 默认密码
                created_at: new Date()
            };
            await this.writeJSONFile(configPath, defaultConfig);
            return defaultConfig;
        }
    }
   async addPort(port) {
        console.log(`添加端口: ${port.port} ${port.download} ${port.upload} ${port.name}`);
        await this.executeCommand(`xs add ${port.port} ${port.download} ${port.upload} ${port.name}`);
   }

   async deletePort(port) {
        console.log(`删除端口: ${port.port}`);
        await this.executeCommand(`xs delete ${port.port}`);
   }

   async addPortArray(ports) {   
       for (const port of ports) {
           await this.addPort(port);
       }
   }

   async deletePortArray(ports) {
       for (const port of ports) {
           await this.deletePort(port);
       }
   }
  async deleteAllPorts() {
    await this.executeCommand(`xs delete-all`);
  }
    async executeCommand(command) {
        const os = require('os');
        // 判断是否为Linux系统
        if (os.platform() === 'linux') {
            const { exec } = require('child_process');
            return new Promise((resolve, reject) => {
                exec(command, (error, stdout, stderr) => {
                    if (error) {
                        reject(error);
                        return;
                    }
                    resolve(stdout);
                });
            });
        } else {
            // Windows系统直接返回true
            return Promise.resolve(true);
        }
    }

    isLinux() {
        const os = require('os');
        return os.platform() === 'linux';
    }
}

module.exports = PortService;