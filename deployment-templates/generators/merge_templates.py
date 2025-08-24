#!/usr/bin/env python3

import sys
import os
import argparse
from pathlib import Path

def merge_template(base_template_path, service_type_dir, output_path, service_name):
    """Merge base template with service-specific parts"""
    
    # Read the base template
    with open(base_template_path, 'r') as f:
        template_content = f.read()
    
    # Define the include patterns and their corresponding files with conditional blocks
    includes = {
        "runtime_install": {
            "file": "runtime_install.yml.j2",
            "start_pattern": "# SERVICE-SPECIFIC INJECTION POINT: Runtime Installation\n    {% if service_runtime_install is defined and service_runtime_install %}\n    {% include 'service-parts/runtime_install.yml.j2' %}\n    {% endif %}",
            "simple_pattern": "{% include 'service-parts/runtime_install.yml.j2' %}"
        },
        "dependency_install": {
            "file": "dependency_install.yml.j2", 
            "start_pattern": "# SERVICE-SPECIFIC INJECTION POINT: Dependency Installation\n    {% if service_dependency_install is defined and service_dependency_install %}\n    {% include 'service-parts/dependency_install.yml.j2' %}\n    {% endif %}",
            "simple_pattern": "{% include 'service-parts/dependency_install.yml.j2' %}"
        },
        "build_tasks": {
            "file": "build_tasks.yml.j2",
            "start_pattern": "# SERVICE-SPECIFIC INJECTION POINT: Build Tasks\n    {% if service_build_tasks is defined and service_build_tasks %}\n    {% include 'service-parts/build_tasks.yml.j2' %}\n    {% endif %}",
            "simple_pattern": "{% include 'service-parts/build_tasks.yml.j2' %}"
        }
    }
    
    # Also handle the systemd service conditional blocks
    systemd_conditionals = [
        {
            "start": "# SERVICE-SPECIFIC INJECTION POINT: Systemd Service\n    {% if service_systemd_service is defined and service_systemd_service %}",
            "end": "    {% endif %}"
        },
        {
            "start": "    # SERVICE STATUS CHECKS (only if systemd service is enabled)\n    {% if service_systemd_service is defined and service_systemd_service %}",
            "end": "    {% endif %}"
        }
    ]
    
    # Find and remove all systemd conditional blocks
    for conditional in systemd_conditionals:
        systemd_conditional_start = conditional["start"]
        systemd_conditional_end = conditional["end"]
        
        if systemd_conditional_start in template_content:
            start_pos = template_content.find(systemd_conditional_start)
            end_pos = template_content.find(systemd_conditional_end, start_pos)
            if end_pos != -1:
                # Extract the content between the conditionals
                systemd_content = template_content[start_pos + len(systemd_conditional_start):end_pos]
                # Replace the entire conditional block with just the content
                if "SERVICE STATUS CHECKS" in systemd_conditional_start:
                    replacement = f"    # SERVICE STATUS CHECKS (only if systemd service is enabled){systemd_content}"
                else:
                    replacement = f"# SERVICE-SPECIFIC INJECTION POINT: Systemd Service{systemd_content}"
                template_content = template_content[:start_pos] + replacement + template_content[end_pos + len(systemd_conditional_end):]
                print(f"  ✓ Removed systemd service conditional block")
    
    # Replace each include with the actual file content
    for include_name, include_info in includes.items():
        filename = include_info["file"]
        service_file_path = os.path.join(service_type_dir, filename)
        
        if os.path.exists(service_file_path):
            # Read the service-specific file
            with open(service_file_path, 'r') as f:
                service_content = f.read()
            
            # Try to replace the full conditional block first
            if include_info["start_pattern"] in template_content:
                replacement = f"# SERVICE-SPECIFIC INJECTION POINT: {include_name.replace('_', ' ').title()}\n    {service_content}"
                template_content = template_content.replace(include_info["start_pattern"], replacement)
                print(f"  ✓ Included {filename} (with conditional)")
            # Fallback to simple include replacement
            elif include_info["simple_pattern"] in template_content:
                template_content = template_content.replace(include_info["simple_pattern"], service_content)
                print(f"  ✓ Included {filename} (simple)")
            else:
                print(f"  - Pattern not found for {filename}")
        else:
            # Remove the conditional block or simple include if file doesn't exist
            if include_info["start_pattern"] in template_content:
                template_content = template_content.replace(include_info["start_pattern"], "")
                print(f"  - Removed conditional block for {filename} (not found)")
            elif include_info["simple_pattern"] in template_content:
                template_content = template_content.replace(include_info["simple_pattern"], "")
                print(f"  - Removed include for {filename} (not found)")
    
    # Write the merged template
    with open(output_path, 'w') as f:
        f.write(template_content)
    
    print(f"✅ Template merged successfully: {output_path}")
    return True

def main():
    parser = argparse.ArgumentParser(description='Merge Ansible templates')
    parser.add_argument('base_template', help='Path to base template file')
    parser.add_argument('service_type_dir', help='Path to service type directory')
    parser.add_argument('output_path', help='Path for output merged template')
    parser.add_argument('service_name', help='Service name')
    
    args = parser.parse_args()
    
    try:
        success = merge_template(args.base_template, args.service_type_dir, args.output_path, args.service_name)
        sys.exit(0 if success else 1)
    except Exception as e:
        print(f"❌ Error merging template: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
