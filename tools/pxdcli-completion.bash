#!/bin/bash
# Bash completion script for pxdcli
# Source this file or install it to /etc/bash_completion.d/ or /usr/local/etc/bash_completion.d/

_pxdcli_completion() {
    local cur prev words cword
    
    # Initialize completion variables manually (compatible without bash-completion)
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev=""
    if [[ $COMP_CWORD -gt 0 ]]; then
        prev="${COMP_WORDS[COMP_CWORD-1]}"
    fi
    
    # Define all available commands
    local commands="generate create update deploy deploy-all redeploy redeploy-all cleanup list status logs restart info ssh nodes help manage ip"
    
    # Define service types for generate command
    local service_types="nodejs python golang rust database static tor-proxy"
    
    # Define runtime variants
    local nodejs_runtimes="node bun"
    local database_types="postgresql mysql redis mongodb"
    
    # Function to get available services from deployments directory
    _get_services() {
        local deployments_dir="${PROJECT_ROOT_OVERRIDE:-$(pwd)}/deployments"
        if [[ -d "$deployments_dir" ]]; then
            find "$deployments_dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort
        fi
    }
    
    # Handle completion based on the command position
    case $COMP_CWORD in
        1)
            # Complete main commands
            COMPREPLY=($(compgen -W "$commands" -- "$cur"))
            return 0
            ;;
        2)
            # Complete based on the previous command
            case "$prev" in
                generate|create)
                    # For generate/create, complete with service name (user input)
                    # Don't provide completions, let user type service name
                    return 0
                    ;;
                deploy|redeploy|cleanup|status|logs|restart|info|ssh|ip|update)
                    # Complete with available service names
                    if [[ "$prev" == "redeploy" ]]; then
                        # For redeploy, also support flags
                        if [[ "$cur" == --* ]]; then
                            COMPREPLY=($(compgen -W "--no-build --force" -- "$cur"))
                        else
                            COMPREPLY=($(compgen -W "$(_get_services)" -- "$cur"))
                        fi
                    else
                        COMPREPLY=($(compgen -W "$(_get_services)" -- "$cur"))
                    fi
                    return 0
                    ;;
                update)
                    # Complete with available service names and update options
                    if [[ "$cur" == --* ]]; then
                        COMPREPLY=($(compgen -W "--dry-run --force --no-backup --verbose --type --file --help" -- "$cur"))
                    else
                        local services="$(_get_services)"
                        COMPREPLY=($(compgen -W "$services" -- "$cur"))
                    fi
                    return 0
                    ;;
                redeploy-all)
                    # Complete with flags only
                    if [[ "$cur" == --* ]]; then
                        COMPREPLY=($(compgen -W "--no-build --force" -- "$cur"))
                    fi
                    return 0
                    ;;
                *)
                    return 0
                    ;;
            esac
            ;;
        *)
            # Handle multi-word completions for commands with options
            if [[ $COMP_CWORD -gt 1 ]]; then
                local cmd="${COMP_WORDS[1]}"
                case "$cmd" in
                    generate)
                        # Handle generate command options
                        case "$prev" in
                            --type)
                                COMPREPLY=($(compgen -W "$service_types" -- "$cur"))
                                return 0
                                ;;
                            --runtime)
                                # Determine runtime options based on service type
                                local service_type=""
                                for ((i=2; i<COMP_CWORD; i++)); do
                                    if [[ "${COMP_WORDS[i]}" == "--type" && $((i+1)) -lt COMP_CWORD ]]; then
                                        service_type="${COMP_WORDS[i+1]}"
                                        break
                                    fi
                                done
                                case "$service_type" in
                                    nodejs)
                                        COMPREPLY=($(compgen -W "$nodejs_runtimes" -- "$cur"))
                                        ;;
                                    database)
                                        COMPREPLY=($(compgen -W "$database_types" -- "$cur"))
                                        ;;
                                    *)
                                        return 0
                                        ;;
                                esac
                                return 0
                                ;;
                            --port|--hostname|--subdomain)
                                # These require user input, no completion
                                return 0
                                ;;
                            *)
                                # Check if we need to complete option flags
                                if [[ "$cur" == --* ]]; then
                                    local generate_options="--type --port --hostname --subdomain --runtime"
                                    COMPREPLY=($(compgen -W "$generate_options" -- "$cur"))
                                    return 0
                                fi
                                return 0
                                ;;
                        esac
                        ;;
                    update)
                        # Handle update command options and service names
                        case "$prev" in
                            --type)
                                COMPREPLY=($(compgen -W "$service_types" -- "$cur"))
                                return 0
                                ;;
                            --file)
                                local template_files="deploy.yml.j2 redeploy.yml.j2 cleanup.yml.j2 group_vars/all.yml.j2"
                                COMPREPLY=($(compgen -W "$template_files" -- "$cur"))
                                return 0
                                ;;
                            *)
                                if [[ "$cur" == --* ]]; then
                                    COMPREPLY=($(compgen -W "--dry-run --force --no-backup --verbose --type --file --help" -- "$cur"))
                                else
                                    # Complete with services not already mentioned
                                    local services="$(_get_services)"
                                    local mentioned_services=""
                                    for ((i=2; i<COMP_CWORD; i++)); do
                                        if [[ "${COMP_WORDS[i]}" != --* && "${COMP_WORDS[i-1]}" != "--type" && "${COMP_WORDS[i-1]}" != "--file" ]]; then
                                            mentioned_services="$mentioned_services ${COMP_WORDS[i]}"
                                        fi
                                    done
                                    
                                    # Filter out already mentioned services
                                    local available_services=""
                                    for service in $services; do
                                        if [[ ! " $mentioned_services " =~ " $service " ]]; then
                                            available_services="$available_services $service"
                                        fi
                                    done
                                    
                                    COMPREPLY=($(compgen -W "$available_services" -- "$cur"))
                                fi
                                return 0
                                ;;
                        esac
                        ;;
                    *)
                        return 0
                        ;;
                esac
            fi
            ;;
    esac
}

# Register the completion function
complete -F _pxdcli_completion pxdcli

# Also register for common variations/aliases
complete -F _pxdcli_completion proxmox-deploy