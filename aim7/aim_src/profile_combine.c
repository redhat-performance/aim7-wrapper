#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

struct probe_info {
	char *function;
	long probes;
};

static char *
skip_spaces(char *ptr)
{
	if (isspace(ptr[0]))
		ptr++;
	return (ptr);
}

int
find_probe(const void *val1, const void *val2)
{
	char *key = (char *) val1;
	struct probe_info *probe_data = (struct probe_info *) val2;

	return (strcmp(key, probe_data->function));
}

static int
probe_sort(const void *val1, const void *val2)
{
	struct probe_info *pd1 = (struct probe_info *) val1;
	struct probe_info *pd2 = (struct probe_info *) val2;

	return (strcmp(pd2->function, pd1->function));
}

static struct probe_info *
pull_data(char *filename, int *entries)
{
	FILE *fd;
	struct probe_info *probe = NULL, *probe_data;
	char buffer[1024];
	char *ptr, *ptr1;;
	int started = 0;
	size_t numb_entries = 0;
	int sort_it;

	fd = fopen(filename, "r");
	if (fd == NULL) {
		perror(filename);
		exit(-1);
	}
	while(fgets(buffer, 1024, fd)) {
		if (started == 0) {
			if (strstr(buffer, "Sampling"))
				started = 1;
			continue;
		}
		if (buffer[0] == '\n')
			continue;
		ptr = strchr(buffer, '\n');
		if (ptr)
			ptr[0] = '\0';
		ptr = skip_spaces(buffer);
		if (numb_entries) {
			probe = (struct probe_info *) bsearch((const void *) ptr, (const void *) probe, 1, numb_entries, find_probe);
		}
		if (probe == NULL) {
			if (numb_entries) {
				probe_data = realloc(probe_data, (numb_entries+1) * sizeof(struct probe_info));
				probe = &probe_data[numb_entries];
			} else {
				probe = probe_data = (struct probe_info *) malloc(sizeof(struct probe_info));
			}
			probe->function = strdup(ptr);
			probe->probes = 0;
			numb_entries++;
			sort_it = 1;
		} else {
			sort_it = 0;
		}
		while (fgets(buffer, 1024,fd)) {
			if (atol(buffer))
				break;
		}
		probe->probes += atol(buffer);
		if (sort_it) {
			qsort(probe_data, numb_entries, sizeof(struct probe_info), probe_sort);
		}
	}
	*entries = numb_entries;
	return (probe_data);


#if 0
    vma_interval_tree_iter_next
    vma_interval_tree_iter_next
    page_referenced
    shrink_active_list
    shrink_lruvec
    shrink_zone
    balance_pgdat
    kswapd
    kthread
    ret_from_fork_nospec_end
    -                kswapd0 (192)
        1
#endif
}

int
main(int argvc, char **argv)
{
	struct probe_info *pd;
	int number_entries;
	pd = pull_data(argv[1], &number_entries);
}
