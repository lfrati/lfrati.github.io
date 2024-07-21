import yaml
from jinja2 import Environment, FileSystemLoader

# Load the YAML data
with open('posts.yaml', 'r') as file:
    data = yaml.safe_load(file)

# Extract entries from the data
entries = data['entries']

# Load the Jinja2 template
file_loader = FileSystemLoader('.')
env = Environment(loader=file_loader)
template = env.get_template('template.html')

# Render the template with data
output = template.render(entries=entries)

# Write the output to a file
with open('index.html', 'w') as file:
    file.write(output)

print("index.html file generated successfully.")