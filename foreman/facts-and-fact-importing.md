# Facts and Fact Importing in Foreman

## Overview

Facts in Foreman are key-value data points that describe the characteristics and configuration of managed hosts. These facts are collected from various configuration management tools (Puppet, Ansible, Chef, Salt) and system monitoring agents, providing a comprehensive inventory of host information that drives provisioning decisions, reporting, and host classification.

## Architecture Overview

The fact system is built around several core components that work together to collect, process, store, and query fact data:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ External Sources│    │ Smart Proxy     │    │ Foreman Core    │
│                 │    │ Layer           │    │                 │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │Puppet Agent │ ├────┤ │Smart Proxy  │ ├────┤ │Hosts API    │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │Ansible      │ ├────┤ │Ansible Proxy│ ├────┤ │HostFact     │ │
│ │Playbook     │ │    │ └─────────────┘ │    │ │Importer     │ │
│ └─────────────┘ │    │ ┌─────────────┐ │    │ └─────────────┘ │
│ ┌─────────────┐ │    │ │Puppet Proxy │ │    │ ┌─────────────┐ │
│ │Chef Node    │ ├────┤ └─────────────┘ │    │ │Plugin       │ │
│ └─────────────┘ │    │                 │    │ │Registry     │ │
│ ┌─────────────┐ │    │                 │    │ └─────────────┘ │
│ │Salt Minion  │ ├────┘                 │    │                 │
│ └─────────────┘ │                      │    │                 │
│ ┌─────────────┐ │                      │    │                 │
│ │RHSM Agent   │ ├──────────────────────┘    │                 │
│ └─────────────┘ │                           │                 │
└─────────────────┘                           └─────────────────┘
           │                                            │
           ▼                                            ▼
┌─────────────────┐                           ┌─────────────────┐
│ Fact Processing │                           │ Data Storage    │
│                 │                           │                 │
│ ┌─────────────┐ │                           │ ┌─────────────┐ │
│ │Fact         │ ├───────────────────────────┤ │FactName     │ │
│ │Importers    │ │                           │ │             │ │
│ └─────────────┘ │                           │ └─────────────┘ │
│ ┌─────────────┐ │                           │ ┌─────────────┐ │
│ │Structured   │ │                           │ │FactValue    │ │
│ │FactImporter │ │                           │ │             │ │
│ └─────────────┘ │                           │ └─────────────┘ │
│ ┌─────────────┐ │                           │ ┌─────────────┐ │
│ │Puppet       │ │                           │ │Host         │ │
│ │FactImporter │ │                           │ │             │ │
│ └─────────────┘ │                           │ └─────────────┘ │
│ ┌─────────────┐ │                           │                 │
│ │Fact Parsers │ ├───────────────────────────┘                 │
│ └─────────────┘ │                                             │
└─────────────────┘                                             │
                                                                 │
                       Relationships:                           │
                       FactName ←→ FactValue (one-to-many)      │
                       Host ←→ FactValue (one-to-many)          │
                       FactName ←→ FactName (ancestry/hierarchy)─┘
```

### Core Components

- **Fact Models**: Data models for storing fact names and values
- **Fact Importers**: Service classes that process and import facts from different sources
- **Fact Parsers**: Classes that extract meaningful data from raw facts
- **Plugin Registry**: Extension mechanism for supporting new fact sources
- **API Endpoints**: RESTful interfaces for accessing fact data

### Fact Sources

Foreman supports multiple fact sources through its plugin architecture:

- **Puppet** (default): Structured facts from Facter
- **Ansible**: Gathered facts from Ansible playbooks
- **Chef**: Node attributes from Chef runs
- **Salt**: Grains from Salt minions
- **RHSM**: Red Hat Subscription Manager data (via Katello)

## Data Model

The fact system uses a hierarchical model to store both simple and structured facts efficiently.

### FactName Model

```ruby
# https://github.com/theforeman/foreman/blob/develop/app/models/fact_name.rb
class FactName < ApplicationRecord
  has_many :fact_values, dependent: :destroy
  has_many_hosts :through => :fact_values
  has_ancestry  # For hierarchical fact relationships

  # Key attributes:
  # - name: Full fact name (e.g., "networking::interfaces::eth0::ip")
  # - short_name: Last component of the fact name (e.g., "ip")
  # - compose: Boolean indicating if this is a composite fact
  # - type: STI type for different fact sources (PuppetFactName, etc.)
end
```

### FactValue Model

```ruby
# https://github.com/theforeman/foreman/blob/develop/app/models/fact_value.rb
class FactValue < ApplicationRecord
  belongs_to :host, class_name: "Host::Base"
  belongs_to :fact_name

  # Key attributes:
  # - value: String representation of the fact value
  # - updated_at: Timestamp of last fact update
end
```

### Database Relationships

```
┌─────────────────────────────┐    ┌─────────────────────────────┐    ┌─────────────────────────────┐
│          Host               │    │        FactValue            │    │        FactName             │
├─────────────────────────────┤    ├─────────────────────────────┤    ├─────────────────────────────┤
│ id (PK)                     │◄──┤ host_id (FK)                │    │ id (PK)                     │
│ name                        │    │ fact_name_id (FK)           ├───►│ name (Full fact name)       │
│ certname                    │    │ value (String)              │    │ short_name (Last component) │
│ last_compile                │    │ updated_at                  │    │ type (STI)                  │
│ location_id                 │    │                             │    │ compose (Boolean)           │
│ organization_id             │    │                             │    │ ancestry (Hierarchical)     │
│                             │    │                             │    │ created_at                  │
│                             │    │                             │    │ updated_at                  │
└─────────────────────────────┘    └─────────────────────────────┘    └─────────────────────────────┘
                                                                                       │
                                                                                       │ ancestry
                                                                                       ▼
                                                                               ┌─────────────────┐
                                                                               │    FactName     │
                                                                               │   (Parent)      │
                                                                               └─────────────────┘

Relationships:
• Host has_many FactValues (1:N)
• FactName has_many FactValues (1:N)
• FactName belongs_to parent FactName via ancestry (hierarchical)
• FactValue belongs_to Host
• FactValue belongs_to FactName
```

### Hierarchical Structure

Facts use a hierarchical structure with `::` as the separator:

```
networking
├── interfaces
│   ├── eth0
│   │   ├── ip (192.168.1.10)
│   │   ├── mac (00:11:22:33:44:55)
│   │   └── netmask (255.255.255.0)
│   └── lo
│       └── ip (127.0.0.1)
└── primary (eth0)
```

## Fact Import Workflow

The fact import process follows a standardized workflow regardless of the source system:

```
1. Fact Submission
   │
   ▼
2. Host Detection (by certname/hostname)
   │
   ▼
3. Fact Normalization
   ├── Remove Empty Values
   ├── Apply Exclusion Rules
   ├── Flatten Structured Facts
   └── Build Hierarchy
   │
   ▼
4. Fact Name Creation (ensure all fact names exist)
   │
   ▼
5. ┌─────────────────┐
   │ Transaction     │
   │ Start           │
   └─────────┬───────┘
             │
   ┌─────────▼─────────┐
   │ 6. Delete Removed │
   │    Facts          │
   └─────────┬─────────┘
             │
   ┌─────────▼─────────┐
   │ 7. Update Existing│
   │    Facts          │
   └─────────┬─────────┘
             │
   ┌─────────▼─────────┐
   │ 8. Add New Facts  │
   └─────────┬─────────┘
             │
   ┌─────────▼─────────┐
   │ 9. Transaction    │
   │    Commit         │
   └─────────┬─────────┘
             │
             ▼
10. Host Field Population (extract OS, arch, etc.)
    │
    ▼
11. Trigger Hooks (:host_facts_updated)
    │
    ▼
12. Complete Import
```

### Detailed Import Process

1. **Fact Submission**
   - Facts arrive via API endpoint `/api/hosts/facts`
   - Host is detected or created based on certname/hostname
   - Fact type (`_type`) determines which importer to use

2. **Fact Normalization** (StructuredFactImporter)
   - Convert all values to strings
   - Remove empty or null values
   - Apply exclusion rules based on regex patterns
   - Flatten nested hashes into hierarchical keys
   - Limit structured facts to prevent database bloat

3. **Fact Name Management**
   - Ensure all fact names exist in `fact_names` table
   - Create missing fact names with proper hierarchy
   - Set `compose` flag for parent nodes

4. **Fact Value Processing** (Transactional)
   - Delete facts no longer present in submitted data
   - Update changed fact values
   - Create new fact values

5. **Host Field Population**
   - Parse facts to extract system information (OS, architecture, etc.)
   - Update host attributes based on fact data
   - Set taxonomies (location/organization) from facts

## API Endpoints

### Fact Submission

```http
PUT /api/hosts/facts
Content-Type: application/json

{
  "name": "hostname.example.com",
  "certname": "hostname.example.com",
  "facts": {
    "_type": "puppet",
    "_timestamp": "2023-10-15T10:30:00Z",
    "operatingsystem": "CentOS",
    "operatingsystemrelease": "7.9",
    "networking": {
      "interfaces": {
        "eth0": {
          "ip": "192.168.1.10",
          "mac": "00:11:22:33:44:55"
        }
      }
    }
  }
}
```

### Fact Retrieval

```http
GET /api/fact_values
GET /api/hosts/:host_id/facts
```

**Query Parameters:**
- `search`: Filter facts using scoped search syntax
- `page` / `per_page`: Pagination controls

**Search Examples:**
```
facts.networking::interfaces::eth0::ip = 192.168.1.10
host = web01.example.com
fact = operatingsystem
organization = Production
```

## Fact Sources and Parsers

### Plugin Registration

Each fact source registers both an importer and a parser:

```ruby
# https://github.com/theforeman/foreman/blob/develop/config/initializers/plugin_parsers.rb
Rails.application.config.to_prepare do
  # Puppet (default)
  Foreman::Plugin.fact_importer_registry.register(:puppet, PuppetFactImporter, true)
  Foreman::Plugin.fact_parser_registry.register(:puppet, PuppetFactParser, true)

  # Ansible
  Foreman::Plugin.fact_importer_registry.register(:ansible, ForemanAnsible::StructuredFactImporter)
  Foreman::Plugin.fact_parser_registry.register(:ansible, AnsibleFactParser)
end
```

### Fact Importers

Fact importers inherit from base classes and customize behavior:

```ruby
# https://github.com/theforeman/foreman/blob/develop/app/services/puppet_fact_importer.rb
class PuppetFactImporter < StructuredFactImporter
  def self.authorized_smart_proxy_features
    'Puppet'
  end

  def fact_name_class
    PuppetFactName
  end
end
```

### Fact Parsers

Parsers extract structured information from raw facts:

```ruby
# https://github.com/theforeman/foreman/blob/develop/app/services/puppet_fact_parser.rb
class PuppetFactParser < FactParser
  def operatingsystem
    # Extract OS information from facts
    # Create or find OperatingSystem record
  end

  def architecture
    # Extract and normalize architecture
    # Create or find Architecture record
  end

  def interfaces
    # Parse network interface information
    # Handle both legacy and modern fact formats
  end
end
```

## Fact Processing Patterns

### Structured vs. Simple Facts

**Simple Facts** (key-value pairs):
```json
{
  "hostname": "web01",
  "operatingsystem": "CentOS",
  "architecture": "x86_64"
}
```

**Structured Facts** (nested data):
```json
{
  "networking": {
    "interfaces": {
      "eth0": {
        "ip": "192.168.1.10",
        "netmask": "255.255.255.0",
        "mac": "00:11:22:33:44:55"
      }
    },
    "primary": "eth0"
  }
}
```

### Fact Processing Pipeline

```
[Raw Fact Submission]
          │
          ▼
    ┌─────────────────┐
    │ Fact Type       │
    │ Detection       │
    │ (_type field)   │
    └─────────┬───────┘
              │
    ┌─────────┼─────────┐
    │ puppet  │ ansible │ other
    ▼         ▼         ▼
┌─────────┐ ┌─────────┐ ┌─────────┐
│ Puppet  │ │ Ansible │ │ Custom  │
│ Fact    │ │ Fact    │ │ Fact    │
│Importer │ │Importer │ │Importer │
└────┬────┘ └────┬────┘ └────┬────┘
     │           │           │
     └─────────┬─┴───────────┘
               ▼
┌─────────────────────────────────────┐
│ StructuredFactImporter.normalize()  │
├─────────────────────────────────────┤
│ 1. Remove Empty Values              │
│ 2. Apply Exclusion Rules            │
│ 3. Flatten Nested Structures        │
│ 4. Build Hierarchy                  │
│ 5. Limit Large Structures           │
└─────────────┬───────────────────────┘
              │
              ▼
     ┌─────────────────┐
     │ Ensure Fact     │
     │ Names Exist     │
     └─────────┬───────┘
               │
               ▼
     ┌─────────────────┐
     │ BEGIN           │
     │ TRANSACTION     │
     └─────────┬───────┘
               │
    ┌─────────▼─────────┐
    │ Database Updates: │
    │ • Delete Removed  │
    │ • Update Changed  │
    │ • Create New      │
    └─────────┬─────────┘
              │
    ┌─────────▼─────────┐     ┌─────────────────┐
    │ COMMIT            │────►│ Parse with      │
    │ TRANSACTION       │     │ FactParser      │
    │ [Success]         │     └─────────┬───────┘
    └───────────────────┘               │
              │                         ▼
              │               ┌─────────────────┐
              │               │ Extract Data:   │
              │               │ • OS Info       │
              │               │ • Architecture  │
              │               │ • Network Info  │
              │               │ • Other Attrs   │
              │               └─────────┬───────┘
              │                         │
              │                         ▼
              │               ┌─────────────────┐
              │               │ Update Host     │
              │               │ Record          │
              │               └─────────┬───────┘
              │                         │
              │                         ▼
              │               ┌─────────────────┐
              │               │ Trigger Hooks   │
              │               └─────────┬───────┘
              │                         │
              │                         ▼
              │               ┌─────────────────┐
              │               │ Complete Import │
              │               └─────────────────┘
              │
              ▼
    ┌─────────────────┐
    │ ROLLBACK        │
    │ TRANSACTION     │
    │ [Error]         │
    └─────────┬───────┘
              │
              ▼
    ┌─────────────────┐
    │ Report Error    │
    │ & Log Details   │
    └─────────────────┘
```

### Fact Flattening Process

Structured facts are flattened into hierarchical keys:

```
Original: {"networking": {"interfaces": {"eth0": {"ip": "192.168.1.10"}}}}
Flattened: {"networking::interfaces::eth0::ip": "192.168.1.10"}
```

This creates intermediate entries:
- `networking` (compose: true, value: nil)
- `networking::interfaces` (compose: true, value: nil)
- `networking::interfaces::eth0` (compose: true, value: nil)
- `networking::interfaces::eth0::ip` (compose: false, value: "192.168.1.10")

### Performance Optimizations

1. **Batch Operations**: Facts are processed in transactions to ensure consistency
2. **Selective Updates**: Only changed fact values are updated
3. **Fact Limiting**: Structured facts are limited to prevent database bloat
4. **Exclusion Rules**: Unwanted facts are filtered out during normalization

## Integration Points

### Host Management

Facts directly influence host provisioning and management:

```ruby
# https://github.com/theforeman/foreman/blob/develop/app/models/host/managed.rb
class Host::Managed
  def populate_fields_from_facts(parser, type, source_proxy)
    # Update host attributes from parsed facts
    self.operatingsystem = parser.operatingsystem
    self.architecture = parser.architecture
    self.domain = parser.domain
    # ... other attributes
  end
end
```

### Smart Proxy Authentication

Fact submission requires proper authentication:
- **Initial Registration**: OAuth consumer key/secret
- **Operational**: mTLS with SSL client certificates
- **Authorization**: Smart proxy features determine which fact types are accepted

### Hooks and Extensions

The fact import process supports hooks for custom processing:

```ruby
host.trigger_hook(:host_facts_updated)
```

Plugins can register hooks to:
- Process custom fact types
- Trigger additional workflows
- Integrate with external systems

## Configuration Settings

Key settings that control fact processing:

- `create_new_host_when_facts_are_uploaded`: Auto-create hosts from facts
- `excluded_facts`: Regex patterns for facts to exclude
- `maximum_structured_facts`: Limit for nested fact structures
- `location_fact` / `organization_fact`: Facts used for taxonomy assignment

## Performance Considerations

### Database Impact

Fact imports can be database-intensive:
- Large fact submissions create many records
- Frequent updates require careful transaction management
- Indexing on `fact_names.name` and `fact_values.host_id` is critical

### Memory Usage

- Structured facts are processed in memory before database operations
- Large fact hierarchies can consume significant memory
- Fact limiting prevents runaway memory consumption

### Monitoring

Key metrics to monitor:
- Fact import duration
- Number of facts processed
- Database transaction times
- Memory usage during import

## Error Handling

The fact import system includes comprehensive error handling:

1. **Validation Errors**: Invalid fact names or values are logged and skipped
2. **Database Errors**: Transaction rollbacks prevent partial imports
3. **Parser Errors**: Malformed facts are logged with detailed error messages
4. **Authorization Errors**: Unauthorized smart proxy submissions are rejected

## Testing Patterns

Fact import testing uses specialized helpers:

```ruby
# https://github.com/theforeman/foreman/blob/develop/test/fact_importer_test_helper.rb
module FactImporterTestHelper
  def allow_transactions_for(fact_importer_class)
    # Allow fact imports in tests
  end
end
```

Common test patterns:
- Mock fact data structures
- Test fact flattening and hierarchy creation
- Verify host attribute population
- Test error handling scenarios

## Security Considerations

### Input Validation

- All fact values are converted to strings
- Fact names must match expected patterns
- Size limits prevent DoS attacks

### Authorization

- Smart proxy registration required for fact submission
- Certificate-based authentication for operational use
- Fact type authorization based on smart proxy features

### Data Privacy

- Sensitive facts can be excluded via configuration
- Fact values are stored as strings (no binary data)
- Host-level access controls apply to fact data

## Example Workflows

### Puppet Fact Submission

```
Puppet Agent → Smart Proxy → Foreman Server → Database

1. [Puppet Agent] ────────────────► [Smart Proxy]
   Submit Puppet facts

2. [Smart Proxy] ─────────────────► [Foreman Server]
   POST /api/hosts/facts
   Content: {facts: {...}, certname: "host.example.com"}

3. [Foreman Server] ──── Detect host by certname

4. [Foreman Server] ──────────────► [Database]
   BEGIN TRANSACTION

5. [Foreman Server] ──────────────► [Database]
   Ensure fact names exist
   (Create missing FactName records)

6. [Foreman Server] ──────────────► [Database]
   DELETE removed facts
   (Facts no longer in submission)

7. [Foreman Server] ──────────────► [Database]
   UPDATE changed facts
   (Modified fact values)

8. [Foreman Server] ──────────────► [Database]
   INSERT new facts
   (New FactValue records)

9. [Foreman Server] ──────────────► [Database]
   COMMIT TRANSACTION

10. [Foreman Server] ─── Parse facts for host attributes
    Extract OS, architecture, network info

11. [Foreman Server] ─────────────► [Database]
    UPDATE host record
    (Set operatingsystem_id, architecture_id, etc.)

12. [Foreman Server] ─────────────► [Smart Proxy]
    HTTP 200 OK

13. [Smart Proxy] ───────────────► [Puppet Agent]
    Success response
```

### Ansible Fact Collection

```
Ansible Playbook → Foreman Plugin → Foreman Server → Database

1. [Ansible Playbook] ───────────► [Foreman Plugin]
   Gather facts callback
   (foreman.foreman.hostvar callback plugin)

2. [Foreman Plugin] ─────────────► [Foreman Server]
   POST /api/hosts/facts
   Content: {
     _type: "ansible",
     facts: {
       ansible_hostname: "web01",
       ansible_networking: {...},
       ansible_memory_mb: {...}
     }
   }

3. [Foreman Plugin] ──── Format facts as structured data
   Convert Ansible facts to Foreman format

4. [Foreman Server] ─────────────► [Database]
   Process structured facts
   (AnsibleFactImporter → StructuredFactImporter)

5. [Foreman Server] ──── Flatten nested structures
   ansible_networking::interfaces::eth0::ipv4::address

6. [Foreman Server] ─────────────► [Database]
   Store hierarchical facts
   (Create FactName hierarchy & FactValue records)

7. [Foreman Server] ─────────────► [Database]
   Update host inventory
   (Extract & store host attributes)

8. [Foreman Server] ─────────────► [Foreman Plugin]
   HTTP 200 OK

9. [Foreman Plugin] ─────────────► [Ansible Playbook]
   Continue execution
   (Facts available for subsequent tasks)
```

## Troubleshooting

### Common Issues

1. **Large Fact Imports**: Monitor memory usage and consider fact exclusions
2. **Missing Facts**: Check exclusion rules and smart proxy authentication
3. **Slow Imports**: Review database indexes and transaction sizes
4. **Parse Errors**: Verify fact format compatibility with parsers

### Debug Information

Enable debug logging for fact imports:
```ruby
Rails.logger.level = :debug
```

Key log messages:
- Fact normalization statistics
- Database operation timings
- Parser extraction results
- Error details with stack traces

## Extension Points

### Custom Fact Importers

Create custom importers by extending base classes:

```ruby
class CustomFactImporter < StructuredFactImporter
  def fact_name_class
    CustomFactName
  end

  def normalize(facts)
    # Custom normalization logic
    super(custom_processed_facts)
  end
end
```

### Custom Fact Parsers

Implement parsers for custom fact extraction:

```ruby
class CustomFactParser < FactParser
  def custom_attribute
    # Extract custom data from facts
    facts[:custom_field]
  end
end
```

### Plugin Registration

Register custom components:

```ruby
Foreman::Plugin.register :custom_facts do
  fact_importer_registry.register(:custom, CustomFactImporter)
  fact_parser_registry.register(:custom, CustomFactParser)
end
```

## Best Practices

### Fact Design

1. **Keep hierarchies shallow**: Deep nesting can impact performance
2. **Use consistent naming**: Follow established fact naming conventions
3. **Limit fact size**: Large fact values should be summarized or excluded
4. **Document custom facts**: Provide clear documentation for custom fact schemas

### Performance

1. **Batch submissions**: Submit facts in reasonable batches
2. **Monitor timing**: Track import duration and optimize bottlenecks
3. **Use exclusions**: Filter out unnecessary facts early
4. **Index properly**: Ensure database indexes support common queries

### Security

1. **Validate inputs**: Always validate fact data before processing
2. **Control access**: Use proper authentication and authorization
3. **Limit exposure**: Don't include sensitive data in facts
4. **Audit changes**: Log fact import activities for security review

## Key Source Code References

For developers working with the facts system, here are links to the most important source files:

### Core Models
- **[FactName](https://github.com/theforeman/foreman/blob/develop/app/models/fact_name.rb)** - Fact name model with hierarchical support
- **[FactValue](https://github.com/theforeman/foreman/blob/develop/app/models/fact_value.rb)** - Fact value model with search capabilities
- **[Host::Managed](https://github.com/theforeman/foreman/blob/develop/app/models/host/managed.rb)** - Host model with fact integration

### Import Services
- **[FactImporter](https://github.com/theforeman/foreman/blob/develop/app/services/fact_importer.rb)** - Base fact import logic
- **[StructuredFactImporter](https://github.com/theforeman/foreman/blob/develop/app/services/structured_fact_importer.rb)** - Handles hierarchical fact structures
- **[PuppetFactImporter](https://github.com/theforeman/foreman/blob/develop/app/services/puppet_fact_importer.rb)** - Puppet-specific fact importer
- **[HostFactImporter](https://github.com/theforeman/foreman/blob/develop/app/services/host_fact_importer.rb)** - High-level fact import orchestration

### Fact Parsers
- **[FactParser](https://github.com/theforeman/foreman/blob/develop/app/services/fact_parser.rb)** - Base fact parsing logic
- **[PuppetFactParser](https://github.com/theforeman/foreman/blob/develop/app/services/puppet_fact_parser.rb)** - Puppet fact extraction and processing

### API Controllers
- **[FactValuesController](https://github.com/theforeman/foreman/blob/develop/app/controllers/api/v2/fact_values_controller.rb)** - API endpoints for fact retrieval
- **[HostsController](https://github.com/theforeman/foreman/blob/develop/app/controllers/api/v2/hosts_controller.rb)** - Host API with fact submission endpoint

### Configuration
- **[Plugin Parsers](https://github.com/theforeman/foreman/blob/develop/config/initializers/plugin_parsers.rb)** - Registration of fact importers and parsers
- **[Plugin Registry](https://github.com/theforeman/foreman/blob/develop/app/registries/foreman/plugin.rb)** - Plugin registration infrastructure

### Testing
- **[Fact Importer Test Helper](https://github.com/theforeman/foreman/blob/develop/test/fact_importer_test_helper.rb)** - Test utilities for fact import testing