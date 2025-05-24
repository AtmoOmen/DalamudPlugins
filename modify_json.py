import os
import json
import time

def modify_links(json_content):
    for item in json_content:
        for key, value in item.items():
            if isinstance(value, str) and 'http' in value:
                if key != 'RepoUrl':
                    item[key] = f"https://gh.atmoomen.top/{value}"
    return json_content

def main():
    pluginmaster_path = 'pluginmaster.json'
    pluginmaster_cn_path = 'pluginmaster-cn.json'

    if not os.path.exists(pluginmaster_path):
        print(f"{pluginmaster_path} does not exist.")
        return

    with open(pluginmaster_path, 'r') as f:
        pluginmaster = json.load(f)

    if pluginmaster == []:
        print("pluginmaster.json is empty.")
        return

    modified_pluginmaster = modify_links(pluginmaster)
    with open(pluginmaster_cn_path, 'w') as f:
        json.dump(modified_pluginmaster, f, indent=4, ensure_ascii=False)

    current_timestamp = int(time.time())
    with open('last-modified.timestamp', 'w') as f:
        f.write(str(current_timestamp))

if __name__ == "__main__":
    main()
