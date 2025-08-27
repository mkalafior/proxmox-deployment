# Feature: Code Redeployment for Proxmox Deploy System

## Epic: Fast Code Updates for Development Workflow

**Status**: Ready for Development  
**Priority**: High  
**Epic Link**: DEV-001  
**Labels**: enhancement, deployment, developer-experience  

---

## Problem Statement

Currently, updating code in deployed services requires running the full `pxdcli deploy` command, which:
- Provisions/recreates entire VM infrastructure
- Reinstalls system packages and runtime
- Takes 3-5 minutes for simple code changes
- Interrupts development flow for iterative testing

**User Story**: As a developer, I want to quickly redeploy only my application code changes without reprovisioning infrastructure, so I can iterate faster during development.

---

## Solution Overview

Implement a new `redeploy` command that focuses solely on code updates for existing, running services. This will be faster than full deployment and safer than simple service restarts.

### Key Principles
- **KISS**: Reuse existing template system and patterns
- **Safety**: Include health checks and rollback capability  
- **Speed**: Skip infrastructure provisioning, focus on code
- **Consistency**: Follow existing CLI patterns and service type abstractions

---

## User Stories

### Story 1: Basic Code Redeployment
**As a** developer  
**I want to** redeploy my code changes to an existing service  
**So that** I can test updates without waiting for full VM provisioning  

**Acceptance Criteria:**
- `pxdcli redeploy <service-name>` command exists
- Works for nodejs, python, golang, static service types
- Skips VM creation and system setup
- Updates application code and restarts service
- Completes in under 60 seconds for typical services

### Story 2: Bulk Redeployment
**As a** developer working on multiple services  
**I want to** redeploy all my code-based services at once  
**So that** I can update my entire application stack quickly  

**Acceptance Criteria:**
- `pxdcli redeploy --all` command exists
- Only affects code-based services (skips databases)
- Shows progress for each service
- Continues on individual service failures

### Story 3: Build Process Integration
**As a** developer using compiled languages or build steps  
**I want** redeployment to handle my build process  
**So that** my latest code changes are properly compiled and deployed  

**Acceptance Criteria:**
- Runs service-specific build tasks (TypeScript, Go compilation, etc.)
- Handles dependency updates when needed
- Option to skip build with `--no-build` flag
- Build failures prevent deployment

---

## Technical Requirements

### Functional Requirements

#### FR-1: Service Type Support
- **Supported**: nodejs, python, golang, static
- **Not Supported**: database, tor-proxy (infrastructure services)
- System validates service type before attempting redeployment

#### FR-2: Deployment Process
1. **Pre-checks**: Verify service exists and VM is accessible
2. **Code Transfer**: Create tar archive and copy to VM (same as deploy)
3. **Dependency Management**: Update dependencies if package files changed
4. **Build Execution**: Run service-specific build tasks
5. **Service Management**: Stop service, replace code, start service
6. **Health Verification**: Confirm service is running and healthy

#### FR-3: Change Detection
- Compare local code with deployed version
- Skip redeployment if no changes detected (unless `--force`)
- Support `.deployignore` file for exclusions

#### FR-4: Error Handling
- Graceful failure with clear error messages
- Service rollback on deployment failure
- Preserve existing service if redeployment fails

### Non-Functional Requirements

#### NFR-1: Performance
- Complete redeployment in <60 seconds for typical services
- <10 seconds for services without build steps
- Minimal downtime during service restart

#### NFR-2: Reliability
- 99% success rate for valid redeployments
- Automatic rollback on health check failures
- Preserve service availability during failures

#### NFR-3: Usability
- Consistent with existing CLI patterns
- Clear progress indicators
- Helpful error messages with suggested fixes

---

## Implementation Tasks

### Task 1: Core Infrastructure
**Story Points**: 8  
**Assignee**: TBD  

**Description**: Create the foundational redeployment system

**Subtasks**:
- Create `redeploy.yml.j2` Ansible playbook template in `deployment-templates/base/`
- Add `redeploy` command to `tools/proxmox-deploy` CLI script
- Generate `redeploy.sh` script for each service (similar to existing `deploy.sh`)
- Implement service type filtering logic

**Acceptance Criteria**:
- `pxdcli redeploy <service>` command executes without errors
- Playbook skips VM provisioning and system setup tasks
- Only code-based services are processed
- Basic error handling for missing services

### Task 2: Service-Specific Templates
**Story Points**: 13  
**Assignee**: TBD  

**Description**: Implement redeployment logic for each supported service type

**Subtasks**:
- Create `redeploy_tasks.yml.j2` for nodejs service type
- Create `redeploy_tasks.yml.j2` for python service type  
- Create `redeploy_tasks.yml.j2` for golang service type
- Create `redeploy_tasks.yml.j2` for static service type
- Implement service-specific build and restart logic

**Acceptance Criteria**:
- Each service type has appropriate build steps
- Dependencies are updated when package files change
- Services restart properly after code update
- Build failures prevent deployment

### Task 3: Health Checks and Validation
**Story Points**: 5  
**Assignee**: TBD  

**Description**: Add health verification and safety checks

**Subtasks**:
- Create `health_check.yml.j2` templates for each service type
- Implement pre-deployment validation (service exists, VM accessible)
- Add post-deployment health verification
- Implement timeout handling for health checks

**Acceptance Criteria**:
- Health checks verify service is responding on expected port
- Failed health checks trigger rollback
- Clear error messages for validation failures
- Configurable health check timeout

### Task 4: CLI Enhancements
**Story Points**: 3  
**Assignee**: TBD  

**Description**: Complete CLI integration and user experience

**Subtasks**:
- Add `redeploy-all` command for bulk operations
- Implement `--no-build` and `--force` flags
- Add progress indicators and status messages
- Update bash completion for new commands

**Acceptance Criteria**:
- All CLI flags work as specified
- Progress is clearly communicated to user
- Tab completion includes new commands
- Help text is updated

### Task 5: Documentation and Testing
**Story Points**: 3  
**Assignee**: TBD  

**Description**: Document the feature and create test scenarios

**Subtasks**:
- Update README.md with redeployment documentation
- Create example workflows for common scenarios
- Test with each supported service type
- Document troubleshooting steps

**Acceptance Criteria**:
- README includes clear usage examples
- All service types tested successfully
- Common error scenarios documented
- Performance benchmarks recorded

---

## Configuration Specification

### Service-Level Configuration
Location: `deployments/<service>/service-config.yml`

```yaml
# Redeployment settings (optional)
redeploy:
  health_check_timeout: 30      # seconds to wait for health check
  skip_build: false             # skip build step by default
  pre_deploy_hook: "scripts/pre-deploy.sh"   # optional script
  post_deploy_hook: "scripts/post-deploy.sh" # optional script
```

### Command Line Interface

```bash
# Basic redeployment
pxdcli redeploy <service-name>

# Bulk redeployment
pxdcli redeploy --all

# Skip build step
pxdcli redeploy <service-name> --no-build

# Force redeploy even if no changes
pxdcli redeploy <service-name> --force
```

---

## File Structure Changes

### New Files to Create
```
deployment-templates/
├── base/
│   └── redeploy.yml.j2          # Main redeployment playbook
└── service-types/
    ├── nodejs/
    │   ├── redeploy_tasks.yml.j2    # Node-specific redeploy steps
    │   └── health_check.yml.j2     # Service health verification
    ├── python/
    │   ├── redeploy_tasks.yml.j2
    │   └── health_check.yml.j2
    ├── golang/
    │   ├── redeploy_tasks.yml.j2
    │   └── health_check.yml.j2
    └── static/
        ├── redeploy_tasks.yml.j2
        └── health_check.yml.j2
```

### Files to Modify
- `tools/proxmox-deploy` - Add redeploy commands
- `tools/pxdcli-completion.bash` - Add command completion
- `deployment-templates/generators/generate.sh` - Generate redeploy.sh scripts
- `README.md` - Document new functionality

---

## Success Metrics

### Performance Targets
- **Redeployment Time**: <60 seconds for services with builds, <10 seconds without
- **Success Rate**: >99% for valid redeployments
- **Downtime**: <5 seconds during service restart

### User Experience Metrics
- **Developer Satisfaction**: Positive feedback on development workflow improvement
- **Usage Adoption**: >80% of developers use redeploy instead of full deploy for code changes
- **Error Recovery**: <2 minutes average time to resolve failed redeployments

---

## Risk Assessment

### High Risk
- **Service Downtime**: Mitigation through health checks and rollback
- **Build Failures**: Mitigation through validation and clear error messages

### Medium Risk  
- **Dependency Conflicts**: Mitigation through proper dependency management
- **Configuration Drift**: Mitigation through consistent template usage

### Low Risk
- **Performance Regression**: Mitigation through benchmarking and optimization
- **CLI Complexity**: Mitigation through consistent patterns and good documentation

---

## Dependencies

### Technical Dependencies
- Existing Ansible playbook system
- Service type template structure
- SSH access to deployed VMs
- Systemd service management

### Team Dependencies
- DevOps team for Ansible template review
- QA team for testing across service types
- Documentation team for user guide updates

---

## Definition of Done

- [ ] All acceptance criteria met for user stories
- [ ] All technical tasks completed and tested
- [ ] Documentation updated (README, help text)
- [ ] Code reviewed and approved
- [ ] Tested with all supported service types
- [ ] Performance benchmarks meet targets
- [ ] Error scenarios handled gracefully
- [ ] CLI completion updated
- [ ] Feature deployed to development environment

---

## Future Enhancements (Out of Scope)

### Phase 2 Considerations
- **Rollback Command**: Quick rollback to previous version
- **Blue-Green Deployment**: Zero-downtime deployment strategy
- **Change Detection Optimization**: Only deploy changed files
- **Deployment Hooks**: Custom pre/post deployment scripts
- **Monitoring Integration**: Deployment success/failure metrics

These enhancements can be considered for future iterations based on user feedback and usage patterns.
