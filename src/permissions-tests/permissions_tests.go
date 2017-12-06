package permissions_tests

import (
	"os/user"
	"syscall"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/ginkgo/extensions/table"
	. "github.com/onsi/gomega"

	"fmt"
	"os"
)

var _ = Describe("Ownership and permissions", func() {
	DescribeTable("for paths",
		func(path, expectedUser, expectedGroup string, expectedPermissions int) {
			fileStat := getFileStat(path)
			By("setting the user owner")
			uid := fmt.Sprint(fileStat.Uid)
			vcap, err := user.Lookup(expectedUser)
			Expect(err).NotTo(HaveOccurred())
			Expect(uid).To(Equal(vcap.Uid))

			By("setting the group owner")
			gid := fmt.Sprint(fileStat.Gid)
			vcapGroup, err := user.LookupGroup(expectedGroup)
			Expect(err).NotTo(HaveOccurred())
			Expect(gid).To(Equal(vcapGroup.Gid))

			By("setting the correct permissions")
			Expect(getPermissions(int(fileStat.Mode))).To(Equal(getPermissions(expectedPermissions)))
		},
		Entry("/var/vcap/store/redis", "/var/vcap/store/redis", "vcap", "vcap", 0750),
		Entry("/var/vcap/store/redis/redis.conf", "/var/vcap/store/redis/redis.conf", "vcap", "vcap", 0640),         //different from on-demand
		Entry("/var/vcap/jobs/dedicated-node/config", "/var/vcap/jobs/dedicated-node/config", "vcap", "vcap", 0750), //different from on-demand
		Entry("/var/vcap/jobs/dedicated-node/config/redis.conf", "/var/vcap/jobs/dedicated-node/config/redis.conf", "vcap", "vcap", 0640),
	)
})

func getPermissions(fileMode int) os.FileMode {
	return os.FileMode(fileMode).Perm()
}

func getFileStat(filePath string) *syscall.Stat_t {
	file, err := os.Stat(filePath)
	Expect(err).NotTo(HaveOccurred())
	return file.Sys().(*syscall.Stat_t)
}
