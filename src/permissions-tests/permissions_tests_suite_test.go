package permissions_tests

import (
	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"

	"testing"
)

func TestPermissionsTests(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "PermissionsTests Suite")
}
