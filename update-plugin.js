const fs = require('fs');

const downloadUrl = process.env.URL || 'http://default.url';
const downloadCount = parseInt(process.env.DOWNLOAD_COUNT, 10) || 0;
const author = process.env.AUTHOR || 'AtmoOmen';
const pluginName = process.env.NAME || 'defaultPluginName';
const internalName = process.env.INTERNAL_NAME || 'defaultInternalName';
const version = process.env.ASSEMBLY_VERSION || '1.0.0.0'; 
const description = process.env.DESCRIPTION || 'None';
const repoUrl = process.env.REPO_URL || 'https://github.com/AtmoOmen';
const punchline = process.env.PUNCHLINE || 'None';
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
    DownloadCount: downloadCount,
    Author: author,
    InternalName: internalName,
    Description: description,
    RepoUrls: repoUrl,
    Punchline: punchline
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
