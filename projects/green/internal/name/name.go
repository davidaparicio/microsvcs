package name

import (
	"os"
)

func GetHostname() string {
	return os.Getenv("HOSTNAME")
}

func GetNamespace() string {
	{
		namespace := os.Getenv("NAMESPACE")
		if namespace != "" {
			return namespace
		}
	}
	{
		namespace, err := os.ReadFile("/var/run/secrets/kubernetes.io/serviceaccount/namespace")
		if err == nil {
			return string(namespace)
		}
	}
	return ""
}
