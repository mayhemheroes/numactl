/* Test numa_is_cpuless_node */
#include "numa.h"
#include <stdio.h>
#include <stdlib.h>

int main(void)
{
	int maxnode, node;
	struct bitmask *cpus;
	int nr_cpuless_nodes = 0;

	if (numa_available() < 0) {
		printf("no numa support in kernel\n");
		exit(1);
	}

	maxnode = numa_max_node();
	cpus = numa_allocate_cpumask();
	if (!cpus) {
		printf("failed to allocate cpumask\n");
		exit(1);
	}

	for (node = 0; node <= maxnode; node++) {
		int weight;
		int is_cpuless;

		if (numa_node_to_cpus(node, cpus) < 0) {
			printf("node %d: numa_node_to_cpus failed\n", node);
			continue;
		}

		weight = numa_bitmask_weight(cpus);
		is_cpuless = numa_is_cpuless_node(node);

		printf("node[%d]: nr_cpus=%d is_cpuless=%s\n",
		       node, weight, is_cpuless ? "true" : "false");

		if (is_cpuless != (weight == 0)) {
			printf("node[%d]: Mismatch!!! nr_cpus=%d but is_cpuless=%s\n",
				node, weight, is_cpuless ? "true" : "false");
			numa_free_cpumask(cpus);
			exit(1);
		}

		if (is_cpuless)
			nr_cpuless_nodes++;
	}

	numa_free_cpumask(cpus);
	printf("Found %d cpuless node(s)\n", nr_cpuless_nodes);
	return 0;
}
