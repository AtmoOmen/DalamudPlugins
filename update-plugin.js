const fs = require('fs');

const pluginName = process.env.NAME || 'defaultPluginName';
const downloadCount = parseInt(process.env.DOWNLOAD_COUNT, 10) || 0;
const version = process.env.VERSION || '1.0.0.0'; 
const downloadUrl = process.env.DOWNLOAD_URL || 'http://default.url';
const path = 'pluginmaster.json';

let plugins;
try {
    const content = fs.readFileSync(path, 'utf8');
    plugins = JSON.parse(content);
} catch (error) {
    console.error('Error reading file:', error);
    plugins = [];
}

const defaultProperties = {
    Name: pluginName,
    DownloadLinkInstall: downloadUrl,
    DownloadLinkTesting: downloadUrl,
    DownloadLinkUpdate: downloadUrl,
    AssemblyVersion: version,
    DownloadCount: downloadCount
};

const itemIndex = plugins.findIndex(p => p.Name === pluginName);
if (itemIndex > -1) {
    plugins[itemIndex] = {...plugins[itemIndex], ...defaultProperties};
} else {
    plugins.push(defaultProperties);
}

try {
    fs.writeFileSync(path, JSON.stringify(plugins, null, 2));
    console.log('Plugin information updated successfully');
} catch (error) {
    console.error('Error writing file:', error);
}
