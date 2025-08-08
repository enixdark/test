#!/usr/bin/env python3
"""
Modular Terraform State to .tf Converter
Converts terraform.tfstate files to Terraform .tf configuration files
with modular structure based on resource types
"""

import json
import sys
import os
import argparse
import re
from typing import Dict, List, Any, Optional, Set
from datetime import datetime
from collections import defaultdict


class ModularTerraformStateConverter:
    def __init__(self, state_file: str, output_dir: str = "generated_terraform"):
        self.state_file = state_file
        self.output_dir = output_dir
        self.state_data = None
        self.resources = []
        self.providers = set()
        self.dependencies = defaultdict(set)
        
        # Define module mappings for different resource types
        self.module_mappings = {
            # AWS Compute
            'aws_instance': 'compute',
            'aws_ec2_instance': 'compute',
            'aws_launch_template': 'compute',
            'aws_autoscaling_group': 'compute',
            'aws_ec2_capacity_reservation': 'compute',
            'aws_spot_instance_request': 'compute',
            
            # AWS Networking
            'aws_vpc': 'networking',
            'aws_subnet': 'networking',
            'aws_route_table': 'networking',
            'aws_internet_gateway': 'networking',
            'aws_nat_gateway': 'networking',
            'aws_vpc_peering_connection': 'networking',
            'aws_vpn_gateway': 'networking',
            'aws_vpn_connection': 'networking',
            'aws_route': 'networking',
            'aws_route_table_association': 'networking',
            'aws_network_acl': 'networking',
            'aws_network_acl_rule': 'networking',
            
            # AWS Security
            'aws_security_group': 'security',
            'aws_security_group_rule': 'security',
            'aws_iam_role': 'security',
            'aws_iam_policy': 'security',
            'aws_iam_user': 'security',
            'aws_iam_group': 'security',
            'aws_kms_key': 'security',
            'aws_kms_alias': 'security',
            
            # AWS Storage
            'aws_ebs_volume': 'storage',
            'aws_ebs_snapshot': 'storage',
            'aws_s3_bucket': 'storage',
            'aws_s3_bucket_policy': 'storage',
            'aws_efs_file_system': 'storage',
            'aws_efs_mount_target': 'storage',
            
            # AWS Database
            'aws_db_instance': 'database',
            'aws_db_subnet_group': 'database',
            'aws_db_parameter_group': 'database',
            'aws_rds_cluster': 'database',
            'aws_dynamodb_table': 'database',
            'aws_elasticache_cluster': 'database',
            'aws_elasticache_subnet_group': 'database',
            
            # AWS Load Balancing
            'aws_lb': 'loadbalancer',
            'aws_lb_target_group': 'loadbalancer',
            'aws_lb_listener': 'loadbalancer',
            'aws_lb_target_group_attachment': 'loadbalancer',
            'aws_elb': 'loadbalancer',
            
            # AWS CDN
            'aws_cloudfront_distribution': 'cdn',
            'aws_cloudfront_origin_access_identity': 'cdn',
            'aws_cloudfront_origin_access_control': 'cdn',
            
            # AWS Monitoring
            'aws_cloudwatch_log_group': 'monitoring',
            'aws_cloudwatch_metric_alarm': 'monitoring',
            'aws_cloudwatch_dashboard': 'monitoring',
            'aws_sns_topic': 'monitoring',
            'aws_sns_topic_subscription': 'monitoring',
            
            # Azure Resources
            'azurerm_virtual_machine': 'compute',
            'azurerm_virtual_machine_scale_set': 'compute',
            'azurerm_virtual_network': 'networking',
            'azurerm_subnet': 'networking',
            'azurerm_network_security_group': 'security',
            'azurerm_storage_account': 'storage',
            'azurerm_sql_database': 'database',
            'azurerm_lb': 'loadbalancer',
            
            # Google Cloud Resources
            'google_compute_instance': 'compute',
            'google_compute_network': 'networking',
            'google_compute_subnetwork': 'networking',
            'google_compute_firewall': 'security',
            'google_storage_bucket': 'storage',
            'google_sql_database_instance': 'database',
            'google_compute_forwarding_rule': 'loadbalancer',
            
            # Kubernetes Resources
            'kubernetes_deployment': 'kubernetes',
            'kubernetes_service': 'kubernetes',
            'kubernetes_pod': 'kubernetes',
            'kubernetes_config_map': 'kubernetes',
            'kubernetes_secret': 'kubernetes',
            
            # Default fallback
            'default': 'misc'
        }
        
    def load_state(self) -> bool:
        """Load and parse the terraform state file"""
        try:
            with open(self.state_file, 'r') as f:
                self.state_data = json.load(f)
            return True
        except FileNotFoundError:
            print(f"Error: State file '{self.state_file}' not found")
            return False
        except json.JSONDecodeError:
            print(f"Error: Invalid JSON in state file '{self.state_file}'")
            return False
    
    def get_module_name(self, resource_type: str) -> str:
        """Get module name based on resource type"""
        return self.module_mappings.get(resource_type, self.module_mappings['default'])
    
    def extract_resources(self) -> List[Dict]:
        """Extract all resources from the state file"""
        if not self.state_data:
            return []
        
        resources = []
        for resource in self.state_data.get('resources', []):
            resource_type = resource.get('type', '')
            resource_name = resource.get('name', '')
            resource_instances = resource.get('instances', [])
            
            for i, instance in enumerate(resource_instances):
                attributes = instance.get('attributes', {})
                resource_id = instance.get('attributes', {}).get('id', f"{resource_name}_{i}")
                
                # Get module name
                module_name = self.get_module_name(resource_type)
                
                resources.append({
                    'type': resource_type,
                    'name': resource_name,
                    'id': resource_id,
                    'attributes': attributes,
                    'module': module_name,
                    'index': i if len(resource_instances) > 1 else None
                })
        
        return resources
    
    def format_value(self, value: Any, indent: int = 0) -> str:
        """Format a value for Terraform configuration"""
        indent_str = "  " * indent
        
        if value is None:
            return "null"
        elif isinstance(value, bool):
            return str(value).lower()
        elif isinstance(value, (int, float)):
            return str(value)
        elif isinstance(value, str):
            if '\n' in value:
                return f'<<-EOF\n{indent_str}  {value}\n{indent_str}EOF'
            else:
                return f'"{value.replace('"', '\\"')}"'
        elif isinstance(value, list):
            if not value:
                return "[]"
            items = []
            for item in value:
                items.append(self.format_value(item, indent + 1))
            return f"[\n{indent_str}  {',\n'.join(items)}\n{indent_str}]"
        elif isinstance(value, dict):
            if not value:
                return "{}"
            items = []
            for k, v in value.items():
                if k.startswith('_') or k in ['id', 'arn']:
                    continue
                formatted_value = self.format_value(v, indent + 1)
                items.append(f'{k} = {formatted_value}')
            return f"{{\n{indent_str}  {',\n'.join(items)}\n{indent_str}}}"
        else:
            return str(value)
    
    def generate_resource_block(self, resource: Dict) -> str:
        """Generate Terraform resource block for a single resource"""
        resource_type = resource['type']
        resource_name = resource['name']
        attributes = resource['attributes']
        
        # Skip internal attributes and computed fields
        skip_attributes = {
            'id', 'arn', 'name', 'tags_all', 'timeouts', 'lifecycle',
            'depends_on', 'provider', 'terraform_meta', 'self_link',
            'unique_id', 'etag', 'fingerprint', 'kms_key_id'
        }
        
        # Generate resource block
        lines = [f'resource "{resource_type}" "{resource_name}" {{']
        
        # Add resource attributes
        for key, value in attributes.items():
            if key in skip_attributes or key.startswith('_'):
                continue
            
            # Skip empty values
            if value is None or value == "":
                continue
                
            formatted_value = self.format_value(value, 1)
            lines.append(f'  {key} = {formatted_value}')
        
        lines.append('}')
        return '\n'.join(lines)
    
    def generate_module_main_tf(self, module_name: str, resources: List[Dict]) -> str:
        """Generate main.tf for a specific module"""
        lines = [
            f'# {module_name.title()} Module',
            f'# Generated by Modular Terraform State to .tf Converter',
            f'# Generated on: {datetime.now().isoformat()}',
            '',
            '# Resources',
            ''
        ]
        
        # Group resources by type within the module
        resources_by_type = defaultdict(list)
        for resource in resources:
            if resource['module'] == module_name:
                resources_by_type[resource['type']].append(resource)
        
        # Generate resource blocks
        for resource_type in sorted(resources_by_type.keys()):
            lines.append(f'# {resource_type} resources')
            for resource in resources_by_type[resource_type]:
                lines.append(self.generate_resource_block(resource))
                lines.append('')
        
        return '\n'.join(lines)
    
    def generate_module_variables_tf(self, module_name: str, resources: List[Dict]) -> str:
        """Generate variables.tf for a specific module"""
        variables = set()
        lines = [
            f'# {module_name.title()} Module Variables',
            f'# Generated by Modular Terraform State to .tf Converter',
            '',
        ]
        
        for resource in resources:
            if resource['module'] == module_name:
                attributes = resource['attributes']
                for key, value in attributes.items():
                    if key.startswith('_') or key in ['id', 'arn']:
                        continue
                    
                    var_name = f"{resource['type']}_{resource['name']}_{key}".replace('-', '_')
                    variables.add(var_name)
        
        for var_name in sorted(variables):
            lines.append(f'variable "{var_name}" {{')
            lines.append('  description = "Auto-generated variable"')
            lines.append('  type        = string')
            lines.append('  default     = null')
            lines.append('}')
            lines.append('')
        
        return '\n'.join(lines)
    
    def generate_module_outputs_tf(self, module_name: str, resources: List[Dict]) -> str:
        """Generate outputs.tf for a specific module"""
        lines = [
            f'# {module_name.title()} Module Outputs',
            f'# Generated by Modular Terraform State to .tf Converter',
            '',
        ]
        
        for resource in resources:
            if resource['module'] == module_name:
                resource_type = resource['type']
                resource_name = resource['name']
                resource_id = resource['attributes'].get('id')
                
                if resource_id:
                    output_name = f"{resource_type}_{resource_name}_id"
                    lines.append(f'output "{output_name}" {{')
                    lines.append(f'  description = "ID of {resource_type}.{resource_name}"')
                    lines.append(f'  value       = {resource_type}.{resource_name}.id')
                    lines.append('}')
                    lines.append('')
        
        return '\n'.join(lines)
    
    def generate_module_versions_tf(self, module_name: str) -> str:
        """Generate versions.tf for a specific module"""
        lines = [
            f'# {module_name.title()} Module Versions',
            f'# Generated by Modular Terraform State to .tf Converter',
            '',
            'terraform {',
            '  required_version = ">= 1.0"',
            '  required_providers {',
        ]
        
        # Add common providers based on module type
        if module_name in ['compute', 'networking', 'security', 'storage', 'database', 'loadbalancer', 'cdn']:
            lines.append('    aws = {')
            lines.append('      source  = "hashicorp/aws"')
            lines.append('      version = "~> 5.0"')
            lines.append('    }')
        elif module_name == 'kubernetes':
            lines.append('    kubernetes = {')
            lines.append('      source  = "hashicorp/kubernetes"')
            lines.append('      version = "~> 2.0"')
            lines.append('    }')
        
        lines.extend([
            '  }',
            '}',
            ''
        ])
        
        return '\n'.join(lines)
    
    def generate_root_main_tf(self, resources: List[Dict]) -> str:
        """Generate root main.tf that calls modules"""
        lines = [
            '# Root Terraform Configuration',
            f'# Generated by Modular Terraform State to .tf Converter',
            f'# Generated on: {datetime.now().isoformat()}',
            '',
            'terraform {',
            '  required_version = ">= 1.0"',
            '  required_providers {',
        ]
        
        # Add providers based on detected resources
        providers = self.detect_providers()
        for provider in sorted(providers):
            lines.append(f'    {provider} = {{')
            lines.append(f'      source  = "hashicorp/{provider}"')
            lines.append('      version = "~> 5.0"')
            lines.append('    }')
        
        lines.extend([
            '  }',
            '}',
            '',
            '# Module calls',
            ''
        ])
        
        # Group resources by module
        modules = defaultdict(list)
        for resource in resources:
            modules[resource['module']].append(resource)
        
        # Generate module calls
        for module_name in sorted(modules.keys()):
            lines.append(f'module "{module_name}" {{')
            lines.append(f'  source = "./modules/{module_name}"')
            lines.append('}')
            lines.append('')
        
        return '\n'.join(lines)
    
    def detect_providers(self) -> Set[str]:
        """Detect providers from resource types"""
        providers = set()
        
        for resource in self.resources:
            resource_type = resource['type']
            if '.' in resource_type:
                provider = resource_type.split('.')[0]
                providers.add(provider)
            else:
                if resource_type.startswith('aws_'):
                    providers.add('aws')
                elif resource_type.startswith('azurerm_'):
                    providers.add('azurerm')
                elif resource_type.startswith('google_'):
                    providers.add('google')
                elif resource_type.startswith('kubernetes_'):
                    providers.add('kubernetes')
        
        return providers
    
    def generate_files(self) -> bool:
        """Generate all Terraform files with modular structure"""
        if not self.load_state():
            return False
        
        self.resources = self.extract_resources()
        if not self.resources:
            print("No resources found in state file")
            return False
        
        # Create output directory
        os.makedirs(self.output_dir, exist_ok=True)
        
        # Group resources by module
        modules = defaultdict(list)
        for resource in self.resources:
            modules[resource['module']].append(resource)
        
        # Generate root files
        root_main_tf = self.generate_root_main_tf(self.resources)
        with open(os.path.join(self.output_dir, 'main.tf'), 'w') as f:
            f.write(root_main_tf)
        
        # Generate module directories and files
        for module_name, module_resources in modules.items():
            module_dir = os.path.join(self.output_dir, 'modules', module_name)
            os.makedirs(module_dir, exist_ok=True)
            
            # Generate module main.tf
            module_main_tf = self.generate_module_main_tf(module_name, module_resources)
            with open(os.path.join(module_dir, 'main.tf'), 'w') as f:
                f.write(module_main_tf)
            
            # Generate module variables.tf
            module_variables_tf = self.generate_module_variables_tf(module_name, module_resources)
            with open(os.path.join(module_dir, 'variables.tf'), 'w') as f:
                f.write(module_variables_tf)
            
            # Generate module outputs.tf
            module_outputs_tf = self.generate_module_outputs_tf(module_name, module_resources)
            with open(os.path.join(module_dir, 'outputs.tf'), 'w') as f:
                f.write(module_outputs_tf)
            
            # Generate module versions.tf
            module_versions_tf = self.generate_module_versions_tf(module_name)
            with open(os.path.join(module_dir, 'versions.tf'), 'w') as f:
                f.write(module_versions_tf)
        
        # Generate root README.md
        readme_content = self.generate_readme(self.resources)
        with open(os.path.join(self.output_dir, 'README.md'), 'w') as f:
            f.write(readme_content)
        
        print(f"Generated modular Terraform files in directory: {self.output_dir}")
        print(f"Root files created:")
        print(f"  - {self.output_dir}/main.tf")
        print(f"  - {self.output_dir}/README.md")
        print(f"\nModules created:")
        for module_name in sorted(modules.keys()):
            print(f"  - {self.output_dir}/modules/{module_name}/")
            print(f"    ├── main.tf")
            print(f"    ├── variables.tf")
            print(f"    ├── outputs.tf")
            print(f"    └── versions.tf")
        
        return True
    
    def generate_readme(self, resources: List[Dict]) -> str:
        """Generate README.md with usage instructions"""
        modules = defaultdict(list)
        for resource in resources:
            modules[resource['module']].append(resource)
        
        lines = [
            '# Modular Terraform Configuration',
            '',
            f'This Terraform configuration was generated from state file: `{self.state_file}`',
            f'Generated on: {datetime.now().isoformat()}',
            '',
            '## Structure',
            '',
            'This configuration uses a modular approach with the following structure:',
            '',
            '```',
            'generated_terraform/',
            '├── main.tf              # Root configuration',
            '├── README.md            # This file',
            '└── modules/',
        ]
        
        for module_name in sorted(modules.keys()):
            resource_count = len(modules[module_name])
            lines.append(f'    ├── {module_name}/           # {module_name.title()} resources ({resource_count})')
            lines.append('    │   ├── main.tf')
            lines.append('    │   ├── variables.tf')
            lines.append('    │   ├── outputs.tf')
            lines.append('    │   └── versions.tf')
        
        lines.extend([
            '```',
            '',
            '## Modules',
            '',
        ])
        
        for module_name in sorted(modules.keys()):
            resource_count = len(modules[module_name])
            resource_types = set(r['type'] for r in modules[module_name])
            lines.append(f'### {module_name.title()} Module')
            lines.append(f'- Resources: {resource_count}')
            lines.append(f'- Types: {", ".join(sorted(resource_types))}')
            lines.append('')
        
        lines.extend([
            '## Usage',
            '',
            '1. Review the generated configuration',
            '2. Configure your providers in root `main.tf`',
            '3. Update variable values as needed',
            '4. Run `terraform init`',
            '5. Run `terraform plan` to verify',
            '6. Run `terraform apply` to create resources',
            '',
            '## Module Organization',
            '',
            'Resources are organized into modules based on their type:',
            '',
            '- **compute**: EC2 instances, launch templates, autoscaling groups',
            '- **networking**: VPC, subnets, route tables, gateways',
            '- **security**: Security groups, IAM roles, KMS keys',
            '- **storage**: EBS volumes, S3 buckets, EFS file systems',
            '- **database**: RDS instances, DynamoDB tables, ElastiCache',
            '- **loadbalancer**: ALB, NLB, target groups, listeners',
            '- **cdn**: CloudFront distributions',
            '- **monitoring**: CloudWatch, SNS topics',
            '- **kubernetes**: K8s deployments, services, pods',
            '- **misc**: Other resources',
        ])
        
        return '\n'.join(lines)
    
    def print_summary(self, resources: List[Dict]):
        """Print a summary of the conversion"""
        print(f"\nModular Conversion Summary:")
        print(f"State file: {self.state_file}")
        print(f"Total resources: {len(resources)}")
        
        # Group by module
        modules = defaultdict(list)
        for resource in resources:
            modules[resource['module']].append(resource)
        
        print(f"\nModules:")
        for module_name in sorted(modules.keys()):
            resource_count = len(modules[module_name])
            resource_types = set(r['type'] for r in modules[module_name])
            print(f"  - {module_name}: {resource_count} resources ({', '.join(sorted(resource_types))})")


def main():
    parser = argparse.ArgumentParser(
        description='Convert Terraform state file to modular .tf configuration files'
    )
    parser.add_argument(
        'state_file',
        help='Path to terraform.tfstate file'
    )
    parser.add_argument(
        '-o', '--output-dir',
        default='generated_terraform',
        help='Output directory for generated files (default: generated_terraform)'
    )
    parser.add_argument(
        '--summary-only',
        action='store_true',
        help='Only print summary without generating files'
    )
    
    args = parser.parse_args()
    
    converter = ModularTerraformStateConverter(args.state_file, args.output_dir)
    
    if not converter.load_state():
        sys.exit(1)
    
    resources = converter.extract_resources()
    converter.print_summary(resources)
    
    if not args.summary_only:
        if converter.generate_files():
            print("\nModular conversion completed successfully!")
            print(f"\nNext steps:")
            print(f"1. cd {args.output_dir}")
            print(f"2. Review the modular structure")
            print(f"3. Configure your providers in main.tf")
            print(f"4. Run terraform init")
            print(f"5. Run terraform plan")
        else:
            print("\nConversion failed!")
            sys.exit(1)


if __name__ == "__main__":
    main() 
